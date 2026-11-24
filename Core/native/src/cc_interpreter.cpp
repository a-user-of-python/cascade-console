// ============================================================================
// cc_interpreter.cpp — Cascade Console Layer 2: the native C++ session
// interpreter implementing Core/facade/cc_facade.h.
//
// This is a line-by-line port of the Python reference implementation
// (repo/Core/python/cc/interpreter.py + errors.py): same grammar (compact
// leading-name forms AND catalog `as` forms), same command names and
// aliases, same numeric error codes, same result strings, same undo rule
// (snapshot BEFORE a mutating command; a failed command leaves no undo
// step). Geometry is delegated to ccgeom.h (Layer 1) — this file contains
// no geometry math beyond expression evaluation and transform matrices
// (representation, exactly as the prototype's geometry.py builds gp_Trsf
// arguments; the backend applies them).
//
// Error translation at the Layer-1 boundary (per cc_facade.h):
//   CCGEOM_ERR_INVALID_ARG -> E2001 INVALID_PARAM
//   CCGEOM_ERR_EDGE_INDEX  -> E2005 BAD_EDGE_INDEX
//   CCGEOM_ERR_EMPTY       -> E2003 EMPTY_RESULT
//   CCGEOM_ERR_OCCT        -> E2002 GEOMETRY_FAILED (message from backend)
//
// Ownership: the session owns every CCGeomShape* in its registry and in
// its undo/redo snapshots; snapshots hold CLONES (ccgeom_clone), so a
// restore never aliases a live object. cc_borrow_shape returns the
// backend handle only in the mc-backend build (see bottom of file).
// ============================================================================
#include "cc_facade.h"
#include "ccgeom.h"
#include "ccsim.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace {

// ---- error codes (mirror Core/python/cc/errors.py exactly) ------------------
enum Codes {
  PARSE = 1001, UNKNOWN_COMMAND = 1002, ARITY = 1003, BAD_EXPRESSION = 1004,
  UNDEFINED_NAME = 1005, DUPLICATE_NAME = 1006, NOTHING_TO_UNDO = 1007,
  NOTHING_TO_REDO = 1008, BAD_NAME = 1009,
  INVALID_PARAM = 2001, GEOMETRY_FAILED = 2002, EMPTY_RESULT = 2003,
  BAD_PROFILE = 2004, BAD_EDGE_INDEX = 2005,
  FILE_NOT_FOUND = 3001, FILE_READ = 3002, EXPORT_FAILED = 3003,
  SCRIPT_FAILED = 3004,
  INTERNAL = 5001, NOT_IMPLEMENTED = 5002
};

struct CCError {
  int code; std::string name; std::string message; int lineNo = 0;
  CCError(int c, std::string n, std::string m) : code(c), name(std::move(n)), message(std::move(m)) {}
};

CCError parseError(const std::string& m) { return CCError(PARSE, "PARSE", m); }
CCError arity(const std::string& cmd, const std::string& m) {
  return CCError(ARITY, "ARITY", "'" + cmd + "': " + m);
}
CCError badExpression(const std::string& tok, const std::string& why) {
  return CCError(BAD_EXPRESSION, "BAD_EXPRESSION", "Could not evaluate '" + tok + "': " + why + ".");
}
CCError undefinedName(const std::string& kind, const std::string& n) {
  return CCError(UNDEFINED_NAME, "UNDEFINED_NAME", "No " + kind + " named '" + n + "' exists yet.");
}
// NOTE (v0.3.0): there is deliberately no duplicateName() error
// constructor anymore — the session layer auto-suffixes a
// same-directory duplicate instead of raising E1006 (see claimName
// and the name-directories comment on CCSession). The DUPLICATE_NAME
// code stays in the table above; the Python reference prototype
// still raises it (documented divergence, FIXLOG v0.3.0).
CCError invalidParam(const std::string& m) { return CCError(INVALID_PARAM, "INVALID_PARAM", m); }

// ---- formatting (match Python's str/format for the values we print) ---------
std::string fmtF(double v, int prec) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.*f", prec, v);
  return buf;
}
std::string fmtPyFloat(double v) {
  // Python str(float): shortest round-trip, integral values get ".0".
  if (v == std::floor(v) && std::fabs(v) < 1e16) {
    char buf[64]; std::snprintf(buf, sizeof(buf), "%.1f", v); return buf;
  }
  char buf[64]; std::snprintf(buf, sizeof(buf), "%.12g", v); return buf;
}
std::string fmtG(double v) {  // for view JSON numbers
  char buf[64]; std::snprintf(buf, sizeof(buf), "%.9g", v); return buf;
}

bool validName(const std::string& n) {
  if (n.empty() || !(std::isalpha((unsigned char)n[0]) || n[0] == '_')) return false;
  for (char c : n) if (!(std::isalnum((unsigned char)c) || c == '_')) return false;
  return true;
}
std::string lower(std::string s) {
  for (auto& c : s) c = (char)std::tolower((unsigned char)c);
  return s;
}

// ---- tokenizer (shlex-like: whitespace split, quotes, # comments) -----------
std::vector<std::string> tokenize(const std::string& line) {
  std::vector<std::string> out;
  std::string cur;
  bool inToken = false, inSingle = false, inDouble = false;
  for (size_t i = 0; i < line.size(); ++i) {
    char c = line[i];
    if (inSingle) {
      if (c == '\'') inSingle = false; else cur += c;
      continue;
    }
    if (inDouble) {
      if (c == '"') inDouble = false;
      else if (c == '\\' && i + 1 < line.size() && (line[i + 1] == '"' || line[i + 1] == '\\')) cur += line[++i];
      else cur += c;
      continue;
    }
    if (c == '#') break;
    if (c == '\'') { inSingle = true; inToken = true; continue; }
    if (c == '"') { inDouble = true; inToken = true; continue; }
    if (c == '\\' && i + 1 < line.size()) { cur += line[++i]; inToken = true; continue; }
    if (std::isspace((unsigned char)c)) {
      if (inToken) { out.push_back(cur); cur.clear(); inToken = false; }
      continue;
    }
    cur += c; inToken = true;
  }
  if (inSingle || inDouble) throw parseError("Could not parse line: No closing quotation.");
  if (inToken) out.push_back(cur);
  return out;
}

// ---- numeric expression evaluator --------------------------------------------
// Grammar (prototype: Python ast over the token with '$' stripped):
//   expr := term (('+'|'-') term)* ; term := factor (('*'|'/'|'%') factor)*
//   factor := unary ('**' factor)? ; unary := ('+'|'-') unary | atom
//   atom := number | ident | '(' expr ')'
struct ExprParser {
  const std::string& tok;
  const std::map<std::string, double>& vars;
  size_t pos = 0;
  ExprParser(const std::string& t, const std::map<std::string, double>& v) : tok(t), vars(v) {}
  [[noreturn]] void fail(const std::string& why) { throw badExpression(tok, why); }
  void skipWs() { while (pos < tok.size() && tok[pos] == ' ') ++pos; }
  bool eat(char c) { skipWs(); if (pos < tok.size() && tok[pos] == c) { ++pos; return true; } return false; }
  double parseExpr() {
    double v = parseTerm();
    for (;;) { if (eat('+')) v += parseTerm(); else if (eat('-')) v -= parseTerm(); else return v; }
  }
  double parseTerm() {
    double v = parseFactor();
    for (;;) {
      if (eat('*')) { if (pos < tok.size() && tok[pos] == '*') fail("unsupported expression"); v *= parseFactor(); }
      else if (eat('/')) { double d = parseFactor(); if (d == 0) fail("division by zero"); v /= d; }
      else if (eat('%')) { double d = parseFactor(); if (d == 0) fail("division by zero"); v = std::fmod(v, d); }
      else return v;
    }
  }
  double parseFactor() {
    double base = parseUnary();
    skipWs();
    if (pos + 1 < tok.size() && tok[pos] == '*' && tok[pos + 1] == '*') {
      pos += 2;
      double ex = parseFactor();
      return std::pow(base, ex);
    }
    return base;
  }
  double parseUnary() {
    if (eat('+')) return parseUnary();
    if (eat('-')) return -parseUnary();
    return parseAtom();
  }
  double parseAtom() {
    skipWs();
    if (pos >= tok.size()) fail("not a number or expression");
    if (eat('(')) { double v = parseExpr(); if (!eat(')')) fail("unsupported expression"); return v; }
    if (std::isdigit((unsigned char)tok[pos]) || tok[pos] == '.') {
      const char* begin = tok.c_str() + pos;
      char* end = nullptr;
      double v = std::strtod(begin, &end);
      if (end == begin) fail("not a number or expression");
      pos += (size_t)(end - begin);
      return v;
    }
    if (std::isalpha((unsigned char)tok[pos]) || tok[pos] == '_') {
      size_t start = pos;
      while (pos < tok.size() && (std::isalnum((unsigned char)tok[pos]) || tok[pos] == '_')) ++pos;
      std::string id = tok.substr(start, pos - start);
      auto it = vars.find(id);
      if (it != vars.end()) return it->second;
      if (id == "pi") return 3.14159265358979323846;
      if (id == "e") return 2.71828182845904523536;
      fail("variable '" + id + "' is not set");
    }
    fail("unsupported expression");
  }
};

// ---- session state --------------------------------------------------------------
struct Snapshot {
  std::map<std::string, CCGeomShape*> objects;  // owned clones
  std::map<std::string, std::vector<std::pair<double, double>>> profiles;
  std::map<std::string, double> vars;
};

const std::set<std::string>& mutatingCommands() {
  static const std::set<std::string> kMut = {
    "set", "box", "cylinder", "sphere", "cone", "torus", "profile",
    "extrude", "union", "cut", "intersect", "fuse", "common", "fillet",
    "chamfer", "translate", "rotate", "copy", "duplicate", "rename",
    "delete", "clear",
    "revolve", "loft", "sweep", "shell", "mirror", "pattern"};
  return kMut;
}

const char* const kHelpLines[] = {
  "set <var> = <expr> — define a parameter usable as $var in numbers",
  "box <name> <w> <d> <h> [at x,y,z] — axis-aligned box from the origin corner",
  "cylinder <name> <r> <h> [at x,y,z] — cylinder, base on XY, axis +Z",
  "sphere <name> <r> [at x,y,z] — sphere centred on the origin",
  "cone <name> <r1> <r2> <h> [at x,y,z] — cone/frustum, base r1 at z=0",
  "torus <name> <ringR> <tubeR> [at x,y,z] — torus in the XY plane",
  "profile <name> x,y x,y x,y ... — closed 2D polygon profile",
  "extrude <name> <profile> <dist> — extrude a profile along +Z",
  "revolve <name> <profile> <angleDeg> — revolve a profile about the Y axis (profile x = radius, y = height; angle <= 360)",
  "loft <name> <profile>@<z> <profile>@<z> [...] [ruled] — loft a solid through profile sections at increasing heights",
  "sweep <name> <profile> <x,y,z> <x,y,z> [...] — sweep a profile along a polyline path",
  "shell <name> <src> <thickness> — closed hollow solid, walls <thickness> mm thick (outside size kept)",
  "mirror <name> <src> <xy|xz|yz> [offset] — mirrored copy across a plane through the origin (or offset along its normal)",
  "pattern <name> <src> linear <count> <dx> <dy> <dz> — fused row of copies",
  "pattern <name> <src> circular <count> <angleDeg> [x|y|z] — fused ring of copies about an axis through the origin (360 = evenly spaced)",
  "union <name> <a> <b> — fuse two solids (catalog: fuse <a> <b> as <name>)",
  "cut <name> <a> <b> — subtract b from a (catalog: cut <a> minus <b> as <name>)",
  "intersect <name> <a> <b> — common volume (catalog: common <a> <b> as <name>)",
  "fillet <name> <src> <radius> [edges i,j,...] — round edges (default: all)",
  "chamfer <name> <src> <dist> [edges i,j,...] — chamfer edges (default: all)",
  "translate <name> <src> <dx> <dy> <dz> — moved copy of src",
  "rotate <name> <src> <ax> <ay> <az> <deg> [about x,y,z] — rotated copy",
  "copy <name> <src> / rename <new> <old> / delete <name> / clear",
  "names live in per-command directories (box:part, cut:part) — a name must be unique only within its directory; a duplicate in the same directory is auto-suffixed (part -> part2); write dir:name when a bare name is ambiguous",
  "list / info <name> / volume <name> — inspect the model",
  "undo / redo / history — command history",
  "export step|stl <path> [name] — write CAD/mesh files",
  "view <path.json> [name] [deflection] — tessellation data for the 3D viewer",
  "run <scriptfile> — execute a .txt/.ccs script of commands",
  "echo <text...> / help [command]",
  "sim material list|show|custom|<object> <name> — simulation materials",
  "sim select|fix|load <object> @face <n> ... — sim boundary conditions",
  "sim mesh size <mm> | sim thermal|static | sim run [<object>]",
  "sim results [view <field> [path]|export <path>] / sim clear [<object>]",
};

}  // namespace

struct CCSession {
  std::map<std::string, CCGeomShape*> objects;  // owned
  std::map<std::string, std::vector<std::pair<double, double>>> profiles;
  std::map<std::string, double> vars;
  ccsim::State sim;  // analysis state (NOT snapshotted: not model state)
  std::vector<Snapshot> undoStack, redoStack;
  std::vector<std::pair<std::string, std::pair<bool, int>>> history;  // line, (ok, code)
  int lastCode = 0; std::string lastName, lastMessage; int lastLine = 0;

  ~CCSession() {
    for (auto& kv : objects) ccgeom_free(kv.second);
    for (auto& s : undoStack) for (auto& kv : s.objects) ccgeom_free(kv.second);
    for (auto& s : redoStack) for (auto& kv : s.objects) ccgeom_free(kv.second);
  }

  // ---- helpers ---------------------------------------------------------------
  Snapshot snapshot() {
    Snapshot s; s.profiles = profiles; s.vars = vars;
    for (auto& kv : objects) s.objects[kv.first] = ccgeom_clone(kv.second);
    return s;
  }
  static void freeSnapshot(Snapshot& s) {
    for (auto& kv : s.objects) ccgeom_free(kv.second);
    s.objects.clear();
  }
  void restore(Snapshot&& s) {
    for (auto& kv : objects) ccgeom_free(kv.second);
    objects = s.objects; s.objects.clear();
    profiles = s.profiles; vars = s.vars;
  }
  void checkName(const std::string& n, const std::string& kind = "object") {
    if (!validName(n))
      throw CCError(BAD_NAME, "BAD_NAME", "'" + n + "' is not a valid " + kind +
                    " name — use letters, digits and underscores, starting with a letter.");
  }

  // ---- name directories (v0.3.0) --------------------------------------
  // Every object and profile lives in a DIRECTORY named after the
  // command that created it (box/, cylinder/, cut/, fillet/, ...).
  // Session keys are qualified "dir:name"; the display name (after the
  // colon) is what the UI shows. Uniqueness is PER-DIRECTORY only: a
  // box named "part" and a cut named "part" coexist as box:part and
  // cut:part. Creating with a display name already taken IN THE SAME
  // directory auto-suffixes (part -> part2 -> part3, incrementing a
  // trailing number) instead of failing — E1006 DUPLICATE_NAME is no
  // longer produced by this session layer (the Python reference
  // prototype keeps the old error; documented divergence, FIXLOG
  // v0.3.0). Aliases share their canonical command's directory:
  // fuse -> union, common -> intersect, duplicate -> copy.
  //
  // RESOLUTION ORDER for an operand token (every operand of every
  // command, the sim host, and the C API's name-taking entry points):
  //   1. "dir:name" qualified token -> that exact key, or UNDEFINED.
  //   2. The context directory, when the operand's role implies one
  //      (extrude's profile operand -> profile/).
  //   3. A bare display name matching exactly ONE key across all
  //      directories -> that key (this keeps every pre-v0.3.0 script
  //      working unchanged, since its names are unique).
  //   4. A bare display name matching SEVERAL keys -> UNDEFINED_NAME
  //      (E1005) whose message lists the directories and shows the
  //      qualified form to use. Never a silent guess.
  static std::string directoryFor(const std::string& cmd) {
    if (cmd == "fuse") return "union";
    if (cmd == "common") return "intersect";
    if (cmd == "duplicate") return "copy";
    return cmd;
  }
  static std::string qualify(const std::string& dir, const std::string& name) {
    return dir + ":" + name;
  }
  static std::string keyDirectory(const std::string& key) {
    auto p = key.find(':');
    return p == std::string::npos ? "" : key.substr(0, p);
  }
  static std::string keyDisplay(const std::string& key) {
    auto p = key.find(':');
    return p == std::string::npos ? key : key.substr(p + 1);
  }
  static bool splitQualified(const std::string& token, std::string& dir, std::string& name) {
    auto p = token.find(':');
    if (p == std::string::npos) return false;
    dir = token.substr(0, p);
    name = token.substr(p + 1);
    return true;
  }
  bool nameTaken(const std::string& dir, const std::string& display) const {
    const std::string key = qualify(dir, display);
    return objects.count(key) || profiles.count(key);
  }
  // Claim a result name inside `dir`: the requested display name when
  // free there, else the first free numeric suffix (trailing number
  // incremented: part -> part2, part2 -> part3). Validates the name.
  std::string claimName(const std::string& dir, const std::string& requested) {
    checkName(requested);
    if (!nameTaken(dir, requested)) return qualify(dir, requested);
    std::string stem = requested;
    long n = 1;
    size_t i = requested.size();
    while (i > 0 && std::isdigit((unsigned char)requested[i - 1])) --i;
    if (i < requested.size()) {
      stem = requested.substr(0, i);
      n = std::atol(requested.c_str() + i);
    }
    for (long k = n + 1;; ++k) {
      std::string cand = stem + std::to_string(k);
      if (!nameTaken(dir, cand)) return qualify(dir, cand);
    }
  }
  std::string resolveObjectKey(const std::string& token, const std::string& contextDir = "") {
    std::string dir, name;
    if (splitQualified(token, dir, name)) {
      const std::string key = qualify(dir, name);
      if (objects.count(key)) return key;
      throw undefinedName("object", token);
    }
    if (!contextDir.empty()) {
      const std::string key = qualify(contextDir, token);
      if (objects.count(key)) return key;
    }
    std::string found, dirs;
    int matches = 0;
    for (auto& kv : objects) {
      if (keyDisplay(kv.first) == token) {
        ++matches;
        found = kv.first;
        if (!dirs.empty()) dirs += ", ";
        dirs += keyDirectory(kv.first);
      }
    }
    if (matches == 1) return found;
    if (matches > 1)
      throw CCError(UNDEFINED_NAME, "UNDEFINED_NAME",
                    "The name '" + token + "' exists in more than one directory (" + dirs +
                    ") — write it qualified, e.g. '" + found + "'.");
    throw undefinedName("object", token);
  }
  std::string resolveProfileKey(const std::string& token) {
    std::string dir, name;
    if (splitQualified(token, dir, name)) {
      const std::string key = qualify(dir, name);
      if (profiles.count(key)) return key;
      throw undefinedName("profile", token);
    }
    const std::string key = qualify("profile", token);
    if (profiles.count(key)) return key;
    throw undefinedName("profile", token);
  }
  bool tryResolveObjectKey(const std::string& token, std::string& keyOut) {
    try {
      keyOut = resolveObjectKey(token);
      return true;
    } catch (CCError&) {
      return false;
    }
  }
  CCGeomShape* object(const std::string& token) {
    return objects[resolveObjectKey(token)];
  }
  double num(const std::string& token) {
    std::string t;
    for (char c : token) if (c != '$') t += c;
    ExprParser p(t, vars);
    double v = p.parseExpr();
    p.skipWs();
    if (p.pos != t.size()) throw badExpression(token, "not a number or expression");
    return v;
  }
  std::vector<double> point(const std::string& token) {
    std::vector<double> out;
    std::stringstream ss(token);
    std::string part;
    while (std::getline(ss, part, ',')) out.push_back(num(part));
    if (out.size() != 2 && out.size() != 3)
      throw parseError("'" + token + "' is not a point — write it as x,y or x,y,z.");
    return out;
  }
  // split '<args...> as <name>' -> (hasAs, name, before)
  bool splitAs(const std::vector<std::string>& args, const std::string& cmd,
               std::string& nameOut, std::vector<std::string>& before) {
    auto it = std::find(args.begin(), args.end(), "as");
    if (it == args.end()) { before = args; return false; }
    size_t idx = (size_t)(it - args.begin());
    if (idx != args.size() - 2) throw arity(cmd, "'as <name>' must be the last two words.");
    nameOut = args[idx + 1];
    before.assign(args.begin(), args.begin() + (ptrdiff_t)idx);
    return true;
  }
  // optional trailing 'at x,y,z'
  bool placement(const std::vector<std::string>& tokens, double at[3]) {
    if (tokens.empty()) return false;
    if (tokens.size() == 2 && tokens[0] == "at") {
      auto pt = point(tokens[1]);
      if (pt.size() != 3) throw parseError("'at' needs a 3D point: at x,y,z.");
      at[0] = pt[0]; at[1] = pt[1]; at[2] = pt[2];
      return true;
    }
    throw arity("placement", "expected 'at x,y,z' at the end of the command.");
  }
  // Wrap a backend call that returns a shape + err code.
  template <typename F>
  CCGeomShape* callShape(const char* op, F&& fn) {
    int e = CCGEOM_OK;
    CCGeomShape* s = fn(&e);
    if (s) return s;
    std::string why = ccgeom_last_error();
    if (e == CCGEOM_ERR_INVALID_ARG) throw invalidParam(why);
    if (e == CCGEOM_ERR_EDGE_INDEX) {
      // Rebuild the prototype's message: needs the edge count — the
      // backend message already carries the detail; keep it.
      throw CCError(BAD_EDGE_INDEX, "BAD_EDGE_INDEX", why);
    }
    if (e == CCGEOM_ERR_EMPTY)
      throw CCError(EMPTY_RESULT, "EMPTY_RESULT",
                    std::string(op) + " produced an empty shape — check the inputs overlap / sizes.");
    throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED",
                  std::string(op) + " failed inside Open CASCADE: " + why);
  }
  template <typename F>
  void callOk(const char* op, F&& fn) {
    int e = CCGEOM_OK;
    int rc = fn(&e);
    if (rc == CCGEOM_OK && e == CCGEOM_OK) return;
    std::string why = ccgeom_last_error();
    throw CCError(EXPORT_FAILED, "EXPORT_FAILED", std::string(op) + " failed: " + why);
  }
  void checkPositive(const char* what, double v) {
    if (!(v > 0)) throw invalidParam(std::string(what) + " must be greater than zero (got " + fmtPyFloat(v) + ").");
  }
  CCGeomShape* place(CCGeomShape* shape, const double* at) {
    if (!at || (at[0] == 0 && at[1] == 0 && at[2] == 0)) return shape;
    double m[12] = {1, 0, 0, at[0], 0, 1, 0, at[1], 0, 0, 1, at[2]};
    CCGeomShape* moved = callShape("translate", [&](int* e) { return ccgeom_transform(shape, m, e); });
    ccgeom_free(shape);
    return moved;
  }
  double volumeOf(CCGeomShape* s) {
    int e = CCGEOM_OK; double v = ccgeom_volume(s, &e);
    if (e != CCGEOM_OK) throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED", std::string("volume failed inside Open CASCADE: ") + ccgeom_last_error());
    return v;
  }
  double areaOf(CCGeomShape* s) {
    int e = CCGEOM_OK; double v = ccgeom_area(s, &e);
    if (e != CCGEOM_OK) throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED", std::string("area failed inside Open CASCADE: ") + ccgeom_last_error());
    return v;
  }
  void bboxOf(CCGeomShape* s, double out[6]) {
    int e = CCGEOM_OK;
    if (ccgeom_bbox(s, out, &e) != CCGEOM_OK)
      throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED", std::string("bbox failed inside Open CASCADE: ") + ccgeom_last_error());
  }
  void countsOf(CCGeomShape* s, int* f, int* ed) {
    int e = CCGEOM_OK;
    if (ccgeom_counts(s, f, ed, &e) != CCGEOM_OK)
      throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED", std::string("counts failed inside Open CASCADE: ") + ccgeom_last_error());
  }

  std::string dispatch(const std::vector<std::string>& tokens);
  std::string executeInternal(const std::string& line, int lineNo);
  std::string runScriptFile(const std::string& path);
};

// ============================================================================
// Command implementations (port of interpreter.py's cmd_* methods)
// ============================================================================
namespace {

std::vector<std::string> tail(const std::vector<std::string>& v, size_t from) {
  if (from >= v.size()) return {};
  return std::vector<std::string>(v.begin() + (ptrdiff_t)from, v.end());
}
std::vector<std::string> head(const std::vector<std::string>& v, size_t n) {
  if (n >= v.size()) return v;
  return std::vector<std::string>(v.begin(), v.begin() + (ptrdiff_t)n);
}

}  // namespace

std::string CCSession::executeInternal(const std::string& line, int lineNo) {
  std::string stripped = line;
  size_t a = stripped.find_first_not_of(" \t\r\n");
  size_t b = stripped.find_last_not_of(" \t\r\n");
  stripped = (a == std::string::npos) ? "" : stripped.substr(a, b - a + 1);
  if (stripped.empty() || stripped[0] == '#') return "";
  try {
    auto tokens = tokenize(line);
    if (tokens.empty()) return "";
    std::string result = dispatch(tokens);
    history.push_back({stripped, {true, 0}});
    return result;
  } catch (CCError& err) {
    if (err.lineNo == 0) err.lineNo = lineNo;
    history.push_back({stripped, {false, err.code}});
    throw err;
  }
}

std::string CCSession::runScriptFile(const std::string& path) {
  std::ifstream fh(path);
  if (!fh) throw CCError(FILE_NOT_FOUND, "FILE_NOT_FOUND", "Script file '" + path + "' does not exist.");
  std::vector<std::string> lines;
  std::string raw;
  while (std::getline(fh, raw)) lines.push_back(raw);
  if (fh.bad()) throw CCError(FILE_READ, "FILE_READ", "Could not read script '" + path + "'.");
  int done = 0;
  for (size_t i = 0; i < lines.size(); ++i) {
    std::string t = lines[i];
    size_t s0 = t.find_first_not_of(" \t\r");
    if (s0 == std::string::npos || t[s0] == '#') continue;
    try {
      executeInternal(lines[i], (int)i + 1);
    } catch (CCError& err) {
      CCError wrapped(SCRIPT_FAILED, "SCRIPT_FAILED",
                      "Script stopped: line " + std::to_string(i + 1) + " failed — " + err.message);
      wrapped.lineNo = (int)i + 1;
      throw wrapped;
    }
    ++done;
  }
  return "Ran " + std::to_string(done) + " command(s) from " + path + ".";
}

// Adapter: ccsim::Host over the session's own helpers (INTEGRATION.md).
struct SimHost : ccsim::Host {
  CCSession& s;
  explicit SimHost(CCSession& sess) : s(sess) {}
  CCGeomShape* object(const std::string& name) override {
    try { return s.object(name); }
    catch (CCError& e) { throw ccsim::Error{e.code, e.name, e.message}; }
  }
  double num(const std::string& token) override {
    try { return s.num(token); }
    catch (CCError& e) { throw ccsim::Error{e.code, e.name, e.message}; }
  }
};

std::string CCSession::dispatch(const std::vector<std::string>& tokens) {
  std::string cmd = lower(tokens[0]);
  std::vector<std::string> args = tail(tokens, 1);
  bool mutating = mutatingCommands().count(cmd) > 0;
  Snapshot snap;
  bool snapped = false;
  if (mutating) { snap = snapshot(); snapped = true; for (auto& s : redoStack) freeSnapshot(s); redoStack.clear(); }
  try {
    std::string result;

    // ---- help / echo -------------------------------------------------------
    if (cmd == "help") {
      if (!args.empty()) {
        std::string name = lower(args[0]);
        for (auto* l : kHelpLines) {
          std::string line = l;
          if (line.rfind(name + " ", 0) == 0) { result = line; goto done; }
        }
        throw CCError(UNKNOWN_COMMAND, "UNKNOWN_COMMAND",
                      "Unknown command '" + args[0] + "'. Type 'help' for the command list.");
      }
      result = "Commands:\n";
      for (size_t i = 0; i < sizeof(kHelpLines) / sizeof(kHelpLines[0]); ++i) {
        if (i) result += "\n";
        result += kHelpLines[i];
      }
      goto done;
    }
    if (cmd == "echo") {
      for (size_t i = 0; i < args.size(); ++i) { if (i) result += " "; result += args[i]; }
      goto done;
    }
    // ---- sim (analysis state; deliberately NOT in mutatingCommands) ----
    if (cmd == "sim") {
      SimHost host(*this);
      try { result = ccsim::execute(sim, host, args); }
      catch (ccsim::Error& e) { throw CCError(e.code, e.name, e.message); }
      goto done;
    }
    // ---- set / clear ---------------------------------------------------------
    if (cmd == "set") {
      if (args.size() != 3 || args[1] != "=") throw arity("set", "write: set <var> = <expr>");
      checkName(args[0], "variable");
      vars[args[0]] = num(args[2]);
      result = args[0] + " = " + fmtPyFloat(vars[args[0]]);
      goto done;
    }
    if (cmd == "clear") {
      for (auto& kv : objects) ccgeom_free(kv.second);
      objects.clear(); profiles.clear();
      result = "Cleared all objects and profiles (variables kept).";
      goto done;
    }
    // ---- primitives ------------------------------------------------------------
    if (cmd == "box" || cmd == "cylinder" || cmd == "sphere" || cmd == "cone" || cmd == "torus") {
      int nNums = (cmd == "box" || cmd == "cone") ? 3 : (cmd == "sphere" ? 1 : 2);
      std::string name; std::vector<std::string> before;
      bool hasAs = splitAs(args, cmd, name, before);
      std::vector<std::string> numToks, rest;
      if (hasAs) {
        numToks = head(before, (size_t)nNums); rest = tail(before, (size_t)nNums);
        if ((int)numToks.size() != nNums)
          throw arity(cmd, "write: " + cmd + " <" + std::to_string(nNums) + " number(s)> [at x,y,z] as <name>");
      } else {
        if (args.size() < 1 + (size_t)nNums)
          throw arity(cmd, "write: " + cmd + " <name> <" + std::to_string(nNums) + " number(s)> [at x,y,z]");
        name = args[0]; numToks = head(tail(args, 1), (size_t)nNums); rest = tail(args, 1 + (size_t)nNums);
      }
      checkName(name);
      std::vector<double> nums;
      for (auto& t : numToks) nums.push_back(num(t));
      double at[3]; bool hasAt = placement(rest, at);
      CCGeomShape* shape = nullptr;
      if (cmd == "box") {
        checkPositive("width", nums[0]); checkPositive("depth", nums[1]); checkPositive("height", nums[2]);
        shape = callShape("box", [&](int* e) { return ccgeom_box(nums[0], nums[1], nums[2], e); });
      } else if (cmd == "cylinder") {
        checkPositive("radius", nums[0]); checkPositive("height", nums[1]);
        shape = callShape("cylinder", [&](int* e) { return ccgeom_cylinder(nums[0], nums[1], e); });
      } else if (cmd == "sphere") {
        checkPositive("radius", nums[0]);
        shape = callShape("sphere", [&](int* e) { return ccgeom_sphere(nums[0], e); });
      } else if (cmd == "cone") {
        checkPositive("base radius", nums[0]); checkPositive("height", nums[2]);
        if (nums[1] < 0) throw invalidParam("top radius must be zero or greater (got " + fmtPyFloat(nums[1]) + ").");
        if (nums[0] == nums[1]) throw invalidParam("cone with equal radii is a cylinder — use 'cylinder'.");
        shape = callShape("cone", [&](int* e) { return ccgeom_cone(nums[0], nums[1], nums[2], e); });
      } else {
        checkPositive("ring radius", nums[0]); checkPositive("tube radius", nums[1]);
        shape = callShape("torus", [&](int* e) { return ccgeom_torus(nums[0], nums[1], e); });
      }
      std::string key = claimName(directoryFor(cmd), name);
      objects[key] = place(shape, hasAt ? at : nullptr);
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    // ---- profile / extrude -------------------------------------------------------
    if (cmd == "profile") {
      if (args.size() < 4) throw arity("profile", "write: profile <name> x,y x,y x,y [...]");
      checkName(args[0], "profile");
      std::vector<std::pair<double, double>> pts;
      for (size_t i = 1; i < args.size(); ++i) {
        auto pt = point(args[i]);
        if (pt.size() != 2) throw parseError("Profile point '" + args[i] + "' must be 2D (x,y).");
        pts.push_back({pt[0], pt[1]});
      }
      if (pts.size() < 3) throw CCError(BAD_PROFILE, "BAD_PROFILE", "A profile needs at least 3 points.");
      std::string key = claimName("profile", args[0]);
      profiles[key] = pts;
      result = "Profile " + keyDisplay(key) + ": " + std::to_string(pts.size()) + " points.";
      goto done;
    }
    if (cmd == "extrude") {
      std::string name, prof, distTok;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() != 2) throw arity("extrude", "write: extrude <profile> <dist> as <name>");
        prof = before[0]; distTok = before[1];
      } else {
        if (args.size() != 3) throw arity("extrude", "write: extrude <name> <profile> <dist>");
        name = args[0]; prof = args[1]; distTok = args[2];
      }
      checkName(name);
      // The profile operand resolves in the profile/ directory first
      // (resolution rule 2), so a profile and an object may share a
      // display name without colliding here.
      std::string profKey = resolveProfileKey(prof);
      auto it = profiles.find(profKey);
      double dist = num(distTok);
      checkPositive("extrude distance", dist);
      std::vector<double> xy;
      for (auto& p : it->second) { xy.push_back(p.first); xy.push_back(p.second); }
      std::string key = claimName("extrude", name);
      objects[key] = callShape("extrude", [&](int* e) { return ccgeom_prism(xy.data(), (int)it->second.size(), dist, e); });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    // ---- v0.4.0 batch 1: revolve / loft / sweep -------------------------------------
    if (cmd == "revolve") {
      std::string name, prof, angleTok;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() != 2) throw arity("revolve", "write: revolve <profile> <angleDeg> as <name>");
        prof = before[0]; angleTok = before[1];
      } else {
        if (args.size() != 3) throw arity("revolve", "write: revolve <name> <profile> <angleDeg>");
        name = args[0]; prof = args[1]; angleTok = args[2];
      }
      checkName(name);
      std::string profKey = resolveProfileKey(prof);
      auto it = profiles.find(profKey);
      double angle = num(angleTok);
      if (!(angle > 0.0) || angle > 360.0)
        throw invalidParam("revolve angle must be in (0, 360] degrees.");
      std::vector<double> xy;
      for (auto& p : it->second) {
        if (p.first < -1e-9)
          throw invalidParam("revolve: profile points must lie on or to the right of the Y axis (x >= 0) — in a revolve profile, x is the radius and y is the height.");
        xy.push_back(p.first); xy.push_back(p.second);
      }
      std::string key = claimName("revolve", name);
      objects[key] = callShape("revolve", [&](int* e) { return ccgeom_revolve(xy.data(), (int)it->second.size(), angle, e); });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    if (cmd == "loft") {
      std::string name;
      std::vector<std::string> sectionToks;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        sectionToks = before;
      } else {
        if (args.size() < 3) throw arity("loft", "write: loft <name> <profile>@<z> <profile>@<z> [...] [ruled]");
        name = args[0]; sectionToks = tail(args, 1);
      }
      checkName(name);
      int ruled = 0;
      if (!sectionToks.empty() &&
          (sectionToks.back() == "ruled" || sectionToks.back() == "smooth")) {
        ruled = sectionToks.back() == "ruled" ? 1 : 0;
        sectionToks.pop_back();
      }
      if (sectionToks.size() < 2)
        throw arity("loft", "write: loft <name> <profile>@<z> <profile>@<z> [...] [ruled] — at least two sections");
      std::vector<const double*> profPtrs;
      std::vector<int> counts;
      std::vector<double> heights;
      std::vector<std::vector<double>> owned;
      for (auto& tok : sectionToks) {
        auto at = tok.rfind('@');
        if (at == std::string::npos)
          throw parseError("loft section '" + tok + "' must be written <profile>@<z>.");
        std::string profKey = resolveProfileKey(tok.substr(0, at));
        auto it = profiles.find(profKey);
        double z = num(tok.substr(at + 1));
        if (!heights.empty() && !(z > heights.back()))
          throw invalidParam("loft section heights must be strictly increasing.");
        heights.push_back(z);
        std::vector<double> xy;
        for (auto& p : it->second) { xy.push_back(p.first); xy.push_back(p.second); }
        owned.push_back(std::move(xy));
        counts.push_back((int)it->second.size());
      }
      for (auto& v : owned) profPtrs.push_back(v.data());
      std::string key = claimName("loft", name);
      objects[key] = callShape("loft", [&](int* e) {
        return ccgeom_loft(profPtrs.data(), counts.data(), heights.data(),
                           (int)owned.size(), ruled, e);
      });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    if (cmd == "sweep") {
      std::string name, prof;
      std::vector<std::string> pathToks;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() < 3) throw arity("sweep", "write: sweep <profile> <x,y,z> <x,y,z> [...] as <name>");
        prof = before[0]; pathToks = tail(before, 1);
      } else {
        if (args.size() < 4) throw arity("sweep", "write: sweep <name> <profile> <x,y,z> <x,y,z> [...]");
        name = args[0]; prof = args[1]; pathToks = tail(args, 2);
      }
      checkName(name);
      std::string profKey = resolveProfileKey(prof);
      auto it = profiles.find(profKey);
      std::vector<double> path;
      for (auto& tok : pathToks) {
        auto pt = point(tok);
        if (pt.size() != 3) throw parseError("Sweep path point '" + tok + "' must be 3D (x,y,z).");
        path.insert(path.end(), pt.begin(), pt.end());
      }
      std::vector<double> xy;
      for (auto& p : it->second) { xy.push_back(p.first); xy.push_back(p.second); }
      std::string key = claimName("sweep", name);
      objects[key] = callShape("sweep", [&](int* e) {
        return ccgeom_sweep(xy.data(), (int)it->second.size(), path.data(),
                            (int)pathToks.size(), e);
      });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    // ---- booleans ------------------------------------------------------------------
    if (cmd == "union" || cmd == "fuse" || cmd == "cut" || cmd == "intersect" || cmd == "common") {
      std::string name; std::vector<std::string> before;
      bool hasAs = splitAs(args, cmd, name, before);
      std::vector<std::string> work;
      for (auto& t : before) if (t != "minus") work.push_back(t);
      std::string a, b;
      if (hasAs) {
        if (work.size() != 2) throw arity(cmd, "write: " + cmd + " <a> <b> as <name>");
        a = work[0]; b = work[1];
      } else {
        if (args.size() != 3) throw arity(cmd, "write: " + cmd + " <name> <a> <b>");
        name = args[0]; a = args[1]; b = args[2];
      }
      checkName(name);
      std::string keyA = resolveObjectKey(a), keyB = resolveObjectKey(b);
      CCGeomShape* sa = objects[keyA]; CCGeomShape* sb = objects[keyB];
      // In-place catalog form ('fuse a b as a'): when the result name
      // is an operand's display name, the result TAKES that operand's
      // qualified key (and directory) and replaces it. Otherwise the
      // result is claimed in this command's directory, auto-suffixed
      // on a same-directory collision — a box and a cut may both be
      // named 'a' without any error.
      std::string resultKey;
      bool inPlace = false;
      if (hasAs && name == keyDisplay(keyA)) { resultKey = keyA; inPlace = true; }
      else if (hasAs && name == keyDisplay(keyB)) { resultKey = keyB; inPlace = true; }
      else resultKey = claimName(directoryFor(cmd), name);
      CCGeomShape* r = nullptr;
      const char* op = (cmd == "cut") ? "cut" : (cmd == "intersect" || cmd == "common") ? "intersect" : "union";
      if (cmd == "cut") r = callShape(op, [&](int* e) { return ccgeom_subtract(sa, sb, e); });
      else if (cmd == "intersect" || cmd == "common") r = callShape(op, [&](int* e) { return ccgeom_intersect(sa, sb, e); });
      else r = callShape(op, [&](int* e) { return ccgeom_unite(sa, sb, e); });
      if (cmd != "intersect" && cmd != "common" && volumeOf(r) <= 1e-9) {
        ccgeom_free(r);
        throw CCError(EMPTY_RESULT, "EMPTY_RESULT", std::string(op) + " produced an empty shape — check the inputs overlap / sizes.");
      }
      // In-place: release the overwritten handle (r is a fresh shape;
      // the operands themselves are never consumed by the boolean).
      if (inPlace) {
        auto existing = objects.find(resultKey);
        if (existing != objects.end() && existing->second != r) ccgeom_free(existing->second);
      }
      objects[resultKey] = r;
      result = "Created " + keyDisplay(resultKey) + ".";
      goto done;
    }
    // ---- finishing --------------------------------------------------------------------
    if (cmd == "fillet" || cmd == "chamfer") {
      std::string name; std::vector<std::string> before;
      bool hasAs = splitAs(args, cmd, name, before);
      std::string src, sizeTok; std::vector<std::string> restToks;
      if (hasAs) {
        if (before.size() < 2) throw arity(cmd, "write: " + cmd + " <src> <size> [edges i,j,...] as <name>");
        src = before[0]; sizeTok = before[1]; restToks = tail(before, 2);
        checkName(name);
      } else {
        if (args.size() != 3 && args.size() != 5)
          throw arity(cmd, "write: " + cmd + " <name> <src> <size> [edges i,j,...]");
        name = args[0]; src = args[1]; sizeTok = args[2]; restToks = tail(args, 3);
        checkName(name);
      }
      // edge list
      std::vector<int> indices; const int* idxPtr = nullptr;
      if (!restToks.empty()) {
        if (restToks.size() == 2 && restToks[0] == "edges") {
          std::stringstream ss(restToks[1]); std::string part;
          while (std::getline(ss, part, ',')) {
            char* end = nullptr;
            long v = std::strtol(part.c_str(), &end, 10);
            if (!end || *end != '\0') throw parseError("'" + restToks[1] + "' is not a list of edge numbers.");
            indices.push_back((int)v);
          }
          idxPtr = indices.data();
        } else {
          throw arity(cmd, "expected 'edges i,j,...'.");
        }
      }
      std::string srcKey = resolveObjectKey(src);
      CCGeomShape* srcShape = objects[srcKey];
      // In-place catalog form ('fillet src 1 as src'): the result
      // takes the source's qualified key; otherwise it is claimed in
      // this command's directory (auto-suffix on collision).
      std::string resultKey;
      bool inPlace = false;
      if (hasAs && name == keyDisplay(srcKey)) { resultKey = srcKey; inPlace = true; }
      else resultKey = claimName(directoryFor(cmd), name);
      double size = num(sizeTok);
      checkPositive(cmd == "fillet" ? "fillet radius" : "chamfer distance", size);
      // BAD_EDGE_INDEX message parity with the prototype (needs the count):
      if (idxPtr) {
        int f = 0, ec = 0; countsOf(srcShape, &f, &ec);
        for (int ix : indices)
          if (ix < 0 || ix >= ec)
            throw CCError(BAD_EDGE_INDEX, "BAD_EDGE_INDEX",
                          "Edge index " + std::to_string(ix) + " is out of range — the shape has " +
                          std::to_string(ec) + " edges (0.." + std::to_string(ec - 1) + ").");
      }
      CCGeomShape* r = (cmd == "fillet")
          ? callShape("fillet", [&](int* e) { return ccgeom_fillet(srcShape, size, idxPtr, (int)indices.size(), e); })
          : callShape("chamfer", [&](int* e) { return ccgeom_chamfer(srcShape, size, idxPtr, (int)indices.size(), e); });
      if (inPlace) {
        auto existing = objects.find(resultKey);
        if (existing != objects.end() && existing->second != r) ccgeom_free(existing->second);
      }
      objects[resultKey] = r;
      result = "Created " + keyDisplay(resultKey) + ".";
      goto done;
    }
    if (cmd == "shell") {
      std::string name, src, sizeTok;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() != 2) throw arity("shell", "write: shell <src> <thickness> as <name>");
        src = before[0]; sizeTok = before[1];
      } else {
        if (args.size() != 3) throw arity("shell", "write: shell <name> <src> <thickness>");
        name = args[0]; src = args[1]; sizeTok = args[2];
      }
      checkName(name);
      double thickness = num(sizeTok);
      checkPositive("shell thickness", thickness);
      CCGeomShape* s = object(src);
      std::string key = claimName("shell", name);
      objects[key] = callShape("shell", [&](int* e) { return ccgeom_shell(s, thickness, e); });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    // ---- transforms ----------------------------------------------------------------------
    if (cmd == "translate") {
      std::string name, src; std::vector<std::string> deltaToks;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() != 4) throw arity("translate", "write: translate <src> <dx> <dy> <dz> as <name>");
        src = before[0]; deltaToks = tail(before, 1);
      } else {
        if (args.size() != 5) throw arity("translate", "write: translate <name> <src> <dx> <dy> <dz>");
        name = args[0]; src = args[1]; deltaToks = tail(args, 2);
      }
      checkName(name);
      double m[12] = {1, 0, 0, num(deltaToks[0]), 0, 1, 0, num(deltaToks[1]), 0, 0, 1, num(deltaToks[2])};
      CCGeomShape* s = object(src);
      std::string key = claimName("translate", name);
      objects[key] = callShape("translate", [&](int* e) { return ccgeom_transform(s, m, e); });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    if (cmd == "rotate") {
      std::string name, src; std::vector<std::string> axisToks, tailToks; std::string angleTok;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() != 5 && before.size() != 7)
          throw arity("rotate", "write: rotate <src> <ax> <ay> <az> <angleDeg> [about x,y,z] as <name>");
        src = before[0]; axisToks = head(tail(before, 1), 3); angleTok = before[4]; tailToks = tail(before, 5);
      } else {
        if (args.size() != 6 && args.size() != 8)
          throw arity("rotate", "write: rotate <name> <src> <ax> <ay> <az> <angleDeg> [about x,y,z]");
        name = args[0]; src = args[1]; axisToks = head(tail(args, 2), 3); angleTok = args[5]; tailToks = tail(args, 6);
      }
      checkName(name);
      double axis[3] = {num(axisToks[0]), num(axisToks[1]), num(axisToks[2])};
      double angle = num(angleTok);
      double centre[3] = {0, 0, 0};
      if (!tailToks.empty()) {
        if (tailToks.size() != 2 || tailToks[0] != "about") throw arity("rotate", "expected 'about x,y,z'.");
        auto pt = point(tailToks[1]);
        if (pt.size() != 3) throw parseError("'about' needs a 3D point: about x,y,z.");
        centre[0] = pt[0]; centre[1] = pt[1]; centre[2] = pt[2];
      }
      double len = std::sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
      if (len < 1e-12) throw invalidParam("Rotation axis must not be the zero vector.");
      double ux = axis[0] / len, uy = axis[1] / len, uz = axis[2] / len;
      double th = angle * 3.14159265358979323846 / 180.0;
      double c = std::cos(th), s = std::sin(th), C = 1 - c;
      double R[9] = {c + ux * ux * C, ux * uy * C - uz * s, ux * uz * C + uy * s,
                     uy * ux * C + uz * s, c + uy * uy * C, uy * uz * C - ux * s,
                     uz * ux * C - uy * s, uz * uy * C + ux * s, c + uz * uz * C};
      // t = centre - R*centre
      double tx = centre[0] - (R[0] * centre[0] + R[1] * centre[1] + R[2] * centre[2]);
      double ty = centre[1] - (R[3] * centre[0] + R[4] * centre[1] + R[5] * centre[2]);
      double tz = centre[2] - (R[6] * centre[0] + R[7] * centre[1] + R[8] * centre[2]);
      double m[12] = {R[0], R[1], R[2], tx, R[3], R[4], R[5], ty, R[6], R[7], R[8], tz};
      CCGeomShape* sh = object(src);
      std::string key = claimName("rotate", name);
      objects[key] = callShape("rotate", [&](int* e) { return ccgeom_transform(sh, m, e); });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    // ---- v0.4.0 batch 1: mirror / pattern (transform compositions) ----------------------
    if (cmd == "mirror") {
      std::string name, src, planeTok, offsetTok = "0";
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() != 2 && before.size() != 3)
          throw arity("mirror", "write: mirror <src> <plane> [offset] as <name>");
        src = before[0]; planeTok = before[1];
        if (before.size() == 3) offsetTok = before[2];
      } else {
        if (args.size() != 3 && args.size() != 4)
          throw arity("mirror", "write: mirror <name> <src> <plane> [offset] — plane is xy, xz or yz");
        name = args[0]; src = args[1]; planeTok = args[2];
        if (args.size() == 4) offsetTok = args[3];
      }
      checkName(name);
      std::string plane = planeTok;
      for (auto& ch : plane) ch = (char)std::tolower((unsigned char)ch);
      int axis = plane == "yz" ? 0 : plane == "xz" ? 1 : plane == "xy" ? 2 : -1;
      if (axis < 0)
        throw invalidParam("mirror plane must be xy, xz or yz (the plane the part flips across).");
      double offset = num(offsetTok);
      double m[12] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};
      m[axis * 4 + axis] = -1.0;
      m[axis * 4 + 3] = 2.0 * offset;
      CCGeomShape* s = object(src);
      std::string key = claimName("mirror", name);
      objects[key] = callShape("mirror", [&](int* e) { return ccgeom_transform(s, m, e); });
      result = "Created " + keyDisplay(key) + ".";
      goto done;
    }
    if (cmd == "pattern") {
      std::string name, src, kindTok;
      std::vector<std::string> restToks;
      std::vector<std::string> before;
      if (splitAs(args, cmd, name, before)) {
        if (before.size() < 3) throw arity("pattern", "write: pattern <src> linear <count> <dx> <dy> <dz> as <name> | pattern <src> circular <count> <angleDeg> [axis] as <name>");
        src = before[0]; kindTok = before[1]; restToks = tail(before, 2);
      } else {
        if (args.size() < 4) throw arity("pattern", "write: pattern <name> <src> linear <count> <dx> <dy> <dz> | pattern <name> <src> circular <count> <angleDeg> [axis]");
        name = args[0]; src = args[1]; kindTok = args[2]; restToks = tail(args, 3);
      }
      checkName(name);
      std::string kind = kindTok;
      for (auto& ch : kind) ch = (char)std::tolower((unsigned char)ch);
      if (kind != "linear" && kind != "circular")
        throw invalidParam("pattern kind must be 'linear' or 'circular'.");
      if (restToks.empty()) throw arity("pattern", "pattern needs a copy count");
      double countD = num(restToks[0]);
      if (countD != std::llround(countD) || countD < 2 || countD > 10000)
        throw invalidParam("pattern count must be a whole number >= 2.");
      int count = (int)std::llround(countD);
      CCGeomShape* srcShape = object(src);
      // Copy k's matrix (identity for k = 0 — the source itself,
      // cloned so the accumulator owns every handle it frees).
      auto copyMatrix = [&](int k, double m[12]) {
        for (int i = 0; i < 12; ++i) m[i] = 0;
        m[0] = m[5] = m[10] = 1.0;
        if (kind == "linear") {
          if (restToks.size() != 4)
            throw arity("pattern", "write: pattern <name> <src> linear <count> <dx> <dy> <dz>");
          m[3] = k * num(restToks[1]);
          m[7] = k * num(restToks[2]);
          m[11] = k * num(restToks[3]);
        } else {
          if (restToks.size() != 2 && restToks.size() != 3)
            throw arity("pattern", "write: pattern <name> <src> circular <count> <angleDeg> [axis x|y|z]");
          double total = num(restToks[1]);
          if (!(total > 0.0) || total > 360.0)
            throw invalidParam("circular pattern angle must be in (0, 360].");
          std::string ax = restToks.size() == 3 ? restToks[2] : "z";
          for (auto& ch : ax) ch = (char)std::tolower((unsigned char)ch);
          if (ax != "x" && ax != "y" && ax != "z")
            throw invalidParam("circular pattern axis must be x, y or z.");
          // A full 360 distributes count copies evenly (no copy
          // duplicates the first); a partial span puts the first
          // copy at 0 and the last exactly on the span.
          double step = (total == 360.0) ? 360.0 / count : total / (count - 1);
          double th = k * step * 3.14159265358979323846 / 180.0;
          double c = std::cos(th), s = std::sin(th);
          if (ax == "z") {
            m[0] = c; m[1] = -s; m[4] = s; m[5] = c;
          } else if (ax == "x") {
            m[5] = c; m[6] = -s; m[9] = s; m[10] = c;
          } else {
            m[0] = c; m[2] = s; m[8] = -s; m[10] = c;
          }
        }
      };
      // Validate the argument shape BEFORE creating anything
      // (copyMatrix throws the arity errors for k = 1 too).
      { double probe[12]; copyMatrix(1, probe); }
      CCGeomShape* acc = ccgeom_clone(srcShape);
      if (!acc)
        throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED",
                      std::string("pattern failed inside Open CASCADE: ") + ccgeom_last_error());
      for (int k = 1; k < count; ++k) {
        double m[12]; copyMatrix(k, m);
        int e = 0;
        CCGeomShape* copy = ccgeom_transform(srcShape, m, &e);
        if (!copy) {
          ccgeom_free(acc);
          throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED",
                        std::string("pattern failed inside Open CASCADE: ") + ccgeom_last_error());
        }
        CCGeomShape* fused = ccgeom_unite(acc, copy, &e);
        ccgeom_free(acc);
        ccgeom_free(copy);
        if (!fused)
          throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED",
                        std::string("pattern failed inside Open CASCADE: ") + ccgeom_last_error());
        acc = fused;
      }
      std::string key = claimName("pattern", name);
      objects[key] = acc;
      result = "Created " + keyDisplay(key) + " (" + std::to_string(count) + " copies).";
      goto done;
    }
    // ---- object management ------------------------------------------------------------------
    if (cmd == "copy") {
      if (args.size() != 2) throw arity("copy", "write: copy <newName> <src>");
      checkName(args[0]);
      CCGeomShape* c = ccgeom_clone(object(args[1]));
      if (!c) throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED", std::string("copy failed inside Open CASCADE: ") + ccgeom_last_error());
      std::string key = claimName("copy", args[0]);
      objects[key] = c;
      result = "Copied " + args[1] + " to " + keyDisplay(key) + ".";
      goto done;
    }
    if (cmd == "duplicate") {
      std::string name; std::vector<std::string> before;
      if (!splitAs(args, cmd, name, before) || before.size() != 1)
        throw arity("duplicate", "write: duplicate <src> as <newName>");
      checkName(name);
      CCGeomShape* c = ccgeom_clone(object(before[0]));
      if (!c) throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED", std::string("duplicate failed inside Open CASCADE: ") + ccgeom_last_error());
      std::string key = claimName("copy", name);
      objects[key] = c;
      result = "Copied " + before[0] + " to " + keyDisplay(key) + ".";
      goto done;
    }
    if (cmd == "rename") {
      std::string newName, oldName; std::vector<std::string> before;
      if (splitAs(args, cmd, newName, before)) {
        if (before.size() != 1) throw arity("rename", "write: rename <oldName> as <newName>");
        oldName = before[0];
      } else {
        if (args.size() != 2) throw arity("rename", "write: rename <newName> <oldName>");
        newName = args[0]; oldName = args[1];
      }
      checkName(newName);
      // A rename keeps the object's directory (the directory records
      // the CREATING command); only the display name changes, claimed
      // within that same directory (auto-suffix on collision).
      std::string oldKey = resolveObjectKey(oldName);
      std::string newKey = (newName == keyDisplay(oldKey))
          ? oldKey
          : claimName(keyDirectory(oldKey), newName);
      CCGeomShape* shape = objects[oldKey];
      if (newKey != oldKey) {
        objects.erase(oldKey);
        objects[newKey] = shape;
      }
      result = "Renamed " + keyDisplay(oldKey) + " to " + keyDisplay(newKey) + ".";
      goto done;
    }
    if (cmd == "delete") {
      if (args.size() != 1) throw arity("delete", "write: delete <name>");
      // Objects first (resolution rules apply, ambiguity included),
      // then profiles.
      std::string dir, nm;
      bool qual = splitQualified(args[0], dir, nm);
      bool objExists = qual ? (objects.count(qualify(dir, nm)) > 0)
                            : [&] { for (auto& kv : objects) if (keyDisplay(kv.first) == args[0]) return true; return false; }();
      if (objExists) {
        std::string key = resolveObjectKey(args[0]);
        auto io = objects.find(key);
        ccgeom_free(io->second);
        objects.erase(io);
        result = "Deleted " + keyDisplay(key) + ".";
      } else {
        bool profExists = qual ? (profiles.count(qualify(dir, nm)) > 0)
                               : (profiles.count(qualify("profile", args[0])) > 0);
        if (!profExists) throw undefinedName("object or profile", args[0]);
        std::string key = resolveProfileKey(args[0]);
        profiles.erase(key);
        result = "Deleted " + keyDisplay(key) + ".";
      }
      goto done;
    }
    if (cmd == "list") {
      std::vector<std::string> lines;
      // Objects print with their qualified key (dir:name) — that IS
      // their identity since v0.3.0; profiles print their display
      // name (their directory is always profile/).
      for (auto& kv : objects)
        lines.push_back("object  " + kv.first + ": volume " + fmtF(volumeOf(kv.second), 3) + " mm^3");
      for (auto& kv : profiles)
        lines.push_back("profile " + keyDisplay(kv.first) + ": " + std::to_string(kv.second.size()) + " points");
      for (auto& kv : vars)
        lines.push_back("var     " + kv.first + " = " + fmtPyFloat(kv.second));
      if (lines.empty()) result = "Nothing defined yet.";
      else for (size_t i = 0; i < lines.size(); ++i) { if (i) result += "\n"; result += lines[i]; }
      goto done;
    }
    if (cmd == "info") {
      if (args.size() != 1) throw arity("info", "write: info <name>");
      CCGeomShape* s = object(args[0]);
      double bb[6]; bboxOf(s, bb);
      int f = 0, ed = 0; countsOf(s, &f, &ed);
      result = args[0] + ": volume " + fmtF(volumeOf(s), 3) + " mm^3, area " + fmtF(areaOf(s), 3) +
               " mm^2, faces " + std::to_string(f) + ", edges " + std::to_string(ed) +
               ", bbox (" + fmtF(bb[0], 3) + "," + fmtF(bb[1], 3) + "," + fmtF(bb[2], 3) + ")..(" +
               fmtF(bb[3], 3) + "," + fmtF(bb[4], 3) + "," + fmtF(bb[5], 3) + ")";
      goto done;
    }
    if (cmd == "volume" || cmd == "measure-volume") {
      if (args.size() != 1) throw arity("volume", "write: volume <name>");
      result = args[0] + " volume = " + fmtF(volumeOf(object(args[0])), 6) + " mm^3";
      goto done;
    }
    if (cmd == "show-vars") {
      if (vars.empty()) result = "No variables set.";
      else {
        bool first = true;
        for (auto& kv : vars) { if (!first) result += "\n"; first = false; result += kv.first + " = " + fmtPyFloat(kv.second); }
      }
      goto done;
    }
    // ---- undo / redo / history ------------------------------------------------------------------
    if (cmd == "undo") {
      if (undoStack.empty()) throw CCError(NOTHING_TO_UNDO, "NOTHING_TO_UNDO", "Nothing to undo.");
      redoStack.push_back(snapshot());
      Snapshot s = std::move(undoStack.back()); undoStack.pop_back();
      restore(std::move(s));
      result = "Undid last command.";
      goto done;
    }
    if (cmd == "redo") {
      if (redoStack.empty()) throw CCError(NOTHING_TO_REDO, "NOTHING_TO_REDO", "Nothing to redo.");
      undoStack.push_back(snapshot());
      Snapshot s = std::move(redoStack.back()); redoStack.pop_back();
      restore(std::move(s));
      result = "Redid command.";
      goto done;
    }
    if (cmd == "history") {
      if (history.empty()) result = "No commands yet.";
      else {
        for (size_t i = 0; i < history.size(); ++i) {
          if (i) result += "\n";
          result += std::to_string(i + 1) + ". ";
          result += history[i].second.first ? "ok  " : ("E" + std::to_string(history[i].second.second));
          result += "  " + history[i].first;
        }
      }
      goto done;
    }
    if (cmd == "shape-history") {
      throw CCError(NOT_IMPLEMENTED, "NOT_IMPLEMENTED",
                    "shape-history is not implemented in the Python prototype (BRepTools_History is not recorded); it is facade-ready in the C++ session layer.");
    }
    // ---- files --------------------------------------------------------------------------------------
    if (cmd == "run") {
      if (args.size() != 1) throw arity("run", "write: run <scriptfile>");
      result = runScriptFile(args[0]);
      goto done;
    }
    if (cmd == "export") {
      if (args.size() != 2 && args.size() != 3) throw arity("export", "write: export step|stl <path> [name]");
      std::string kind = lower(args[0]);
      if (kind != "step" && kind != "stl") throw arity("export", "first argument must be 'step' or 'stl'.");
      std::vector<std::pair<std::string, CCGeomShape*>> targets;
      if (args.size() == 3) targets.push_back({args[2], object(args[2])});
      else {
        if (objects.empty()) throw undefinedName("object", "");
        for (auto& kv : objects) targets.push_back(kv);
      }
      std::vector<std::string> written;
      for (auto& t : targets) {
        std::string path = args[1];
        if (targets.size() > 1) {
          // Per-target file names use the DISPLAY name — the
          // qualified key's ':' is not a portable file-name character.
          std::string disp = keyDisplay(t.first);
          size_t dot = path.find_last_of('.');
          size_t slash = path.find_last_of('/');
          if (dot != std::string::npos && (slash == std::string::npos || dot > slash))
            path = path.substr(0, dot) + "_" + disp + path.substr(dot);
          else path = path + "_" + disp;
        }
        if (kind == "step") callOk("export-step", [&](int* e) { return ccgeom_export_step(t.second, path.c_str(), e); });
        else callOk("export-stl", [&](int* e) { return ccgeom_export_stl(t.second, path.c_str(), e); });
        written.push_back(path);
      }
      result = "Exported: ";
      for (size_t i = 0; i < written.size(); ++i) { if (i) result += ", "; result += written[i]; }
      goto done;
    }
    if (cmd == "export-step" || cmd == "export-stl") {
      if (args.size() != 2) throw arity(cmd, "write: " + cmd + " <shape> <file>");
      CCGeomShape* s = object(args[0]);
      if (cmd == "export-step") callOk("export-step", [&](int* e) { return ccgeom_export_step(s, args[1].c_str(), e); });
      else callOk("export-stl", [&](int* e) { return ccgeom_export_stl(s, args[1].c_str(), e); });
      result = "Exported " + args[0] + " to " + args[1] + ".";
      goto done;
    }
    if (cmd == "view") {
      if (args.empty() || args.size() > 3) throw arity("view", "write: view <path.json> [name] [deflection]");
      std::vector<std::pair<std::string, CCGeomShape*>> targets;
      if (args.size() >= 2) {
        std::string key = resolveObjectKey(args[1]);
        targets.push_back({key, objects[key]});
      }
      else for (auto& kv : objects) targets.push_back(kv);
      if (targets.empty()) throw undefinedName("object", "");
      double deflection = args.size() == 3 ? num(args[2]) : 0.5;
      checkPositive("tessellation deflection", deflection);
      std::string json = "{\"format\": \"cascade-console-view\", \"version\": 1, \"units\": \"mm\", \"objects\": [";
      long totalTris = 0;
      for (size_t oi = 0; oi < targets.size(); ++oi) {
        float* verts = nullptr; int* idx = nullptr; int vc = 0, ic = 0;
        int e = CCGEOM_OK;
        if (ccgeom_tessellate(targets[oi].second, deflection, &verts, &vc, &idx, &ic, &e) != CCGEOM_OK)
          throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED", std::string("view failed inside Open CASCADE: ") + ccgeom_last_error());
        double bb[6]; bboxOf(targets[oi].second, bb);
        if (oi) json += ", ";
        json += "{\"name\": \"" + targets[oi].first + "\", \"vertices\": [";
        for (int i = 0; i < vc * 3; ++i) { if (i) json += ", "; json += fmtG(verts[i]); }
        json += "], \"indices\": [";
        for (int i = 0; i < ic; ++i) { if (i) json += ", "; json += std::to_string(idx[i]); }
        json += "], \"triangleCount\": " + std::to_string(ic / 3);
        json += ", \"volume\": " + fmtG(volumeOf(targets[oi].second));
        json += ", \"bbox\": [";
        for (int i = 0; i < 6; ++i) { if (i) json += ", "; json += fmtG(bb[i]); }
        json += "]}";
        totalTris += ic / 3;
        ccgeom_free_buffer(verts); ccgeom_free_buffer(idx);
      }
      json += "]}";
      std::ofstream out(args[0]);
      if (!out) throw CCError(EXPORT_FAILED, "EXPORT_FAILED", "Could not write view data to '" + args[0] + "'.");
      out << json;
      if (!out) throw CCError(EXPORT_FAILED, "EXPORT_FAILED", "Could not write view data to '" + args[0] + "'.");
      result = "View data written to " + args[0] + ": " + std::to_string(targets.size()) +
               " object(s), " + std::to_string(totalTris) + " triangles.";
      goto done;
    }

    throw CCError(UNKNOWN_COMMAND, "UNKNOWN_COMMAND",
                  "Unknown command '" + tokens[0] + "'. Type 'help' for the command list.");

  done:
    if (snapped) undoStack.push_back(std::move(snap));
    return result;
  } catch (...) {
    if (snapped) freeSnapshot(snap);
    throw;
  }
}

// ============================================================================
// C API (cc_facade.h)
// ============================================================================
namespace {
char* dupStr(const std::string& s) {
  char* p = (char*)std::malloc(s.size() + 1);
  if (p) std::memcpy(p, s.c_str(), s.size() + 1);
  return p;
}
void setLast(CCSession* s, const CCError& e) {
  s->lastCode = e.code; s->lastName = e.name; s->lastMessage = e.message; s->lastLine = e.lineNo;
}
void clearLast(CCSession* s) {
  s->lastCode = 0; s->lastName.clear(); s->lastMessage.clear(); s->lastLine = 0;
}
}  // namespace

extern "C" {

CCSession* cc_session_create(void) { return new CCSession(); }

void cc_session_destroy(CCSession* s) { delete s; }

int cc_execute(CCSession* s, const char* line, char** outResult) {
  if (!s || !line) return INTERNAL;
  try {
    std::string r = s->executeInternal(line, 0);
    clearLast(s);
    if (outResult) *outResult = dupStr(r);
    return 0;
  } catch (CCError& e) {
    setLast(s, e);
    if (outResult) *outResult = nullptr;
    return e.code;
  } catch (const std::exception& ex) {
    CCError e(INTERNAL, "INTERNAL", std::string("Internal error: ") + ex.what());
    setLast(s, e);
    if (outResult) *outResult = nullptr;
    return INTERNAL;
  }
}

int cc_execute_script(CCSession* s, const char* path, char** outResult) {
  if (!s || !path) return INTERNAL;
  try {
    std::string r = s->runScriptFile(path);
    clearLast(s);
    if (outResult) *outResult = dupStr(r);
    return 0;
  } catch (CCError& e) {
    setLast(s, e);
    if (outResult) *outResult = nullptr;
    return e.code;
  } catch (const std::exception& ex) {
    CCError e(INTERNAL, "INTERNAL", std::string("Internal error: ") + ex.what());
    setLast(s, e);
    if (outResult) *outResult = nullptr;
    return INTERNAL;
  }
}

int cc_last_error_code(CCSession* s) { return s ? s->lastCode : 0; }
const char* cc_last_error_name(CCSession* s) { return s ? s->lastName.c_str() : ""; }
const char* cc_last_error_message(CCSession* s) { return s ? s->lastMessage.c_str() : ""; }
int cc_last_error_line(CCSession* s) { return s ? s->lastLine : 0; }

int cc_object_count(CCSession* s) { return s ? (int)s->objects.size() : 0; }

const char* cc_object_name(CCSession* s, int index) {
  if (!s || index < 0) return nullptr;
  int i = 0;
  for (auto& kv : s->objects) {
    if (i == index) return kv.first.c_str();
    ++i;
  }
  return nullptr;
}

int cc_profile_count(CCSession* s) { return s ? (int)s->profiles.size() : 0; }

const char* cc_profile_name(CCSession* s, int index) {
  if (!s || index < 0) return nullptr;
  int i = 0;
  for (auto& kv : s->profiles) {
    if (i == index) return kv.first.c_str();
    ++i;
  }
  return nullptr;
}

int cc_object_stats(CCSession* s, const char* name, double* volume, double* area,
                    double bboxOut[6], int* faces, int* edges) {
  if (!s || !name) return UNDEFINED_NAME;
  // Name-taking C API entry points resolve through the same
  // directory rules as command operands (v0.3.0).
  std::string key;
  if (!s->tryResolveObjectKey(name, key)) return UNDEFINED_NAME;
  auto it = s->objects.find(key);
  if (it == s->objects.end()) return UNDEFINED_NAME;
  try {
    if (volume) *volume = s->volumeOf(it->second);
    if (area) *area = s->areaOf(it->second);
    if (bboxOut) s->bboxOf(it->second, bboxOut);
    if (faces || edges) { int f = 0, e = 0; s->countsOf(it->second, &f, &e); if (faces) *faces = f; if (edges) *edges = e; }
    return 0;
  } catch (CCError& e) {
    setLast(s, e);
    return e.code;
  }
}

struct MCFacadeShape* cc_borrow_shape(CCSession* s, const char* name) {
  if (!s || !name) return nullptr;
  std::string key;
  if (!s->tryResolveObjectKey(name, key)) return nullptr;
  auto it = s->objects.find(key);
  if (it == s->objects.end()) return nullptr;
  // ccgeom_native_handle is backend-defined: the mc backend returns the
  // MCFacadeShape*; the direct-OCCT and mock backends return nullptr
  // (their native handle is not an MCFacadeShape — documented in
  // ccgeom.h's backend notes).
  return (struct MCFacadeShape*)ccgeom_native_handle(it->second);
}

int cc_view_data(CCSession* s, const char* nameOrNull, double deflectionMM,
                 CCViewData** outObjects, int* outCount) {
  if (!s || !outObjects || !outCount) return INTERNAL;
  *outObjects = nullptr; *outCount = 0;
  if (!(deflectionMM > 0)) {
    CCError e(INVALID_PARAM, "INVALID_PARAM", "tessellation deflection must be greater than zero.");
    setLast(s, e);
    return e.code;
  }
  std::vector<std::pair<std::string, CCGeomShape*>> targets;
  if (nameOrNull) {
    std::string key;
    try {
      key = s->resolveObjectKey(nameOrNull);
    } catch (CCError& e) {
      setLast(s, e);
      return e.code;
    }
    targets.push_back({key, s->objects[key]});
  } else {
    for (auto& kv : s->objects) targets.push_back(kv);
  }
  CCViewData* arr = (CCViewData*)std::calloc(targets.empty() ? 1 : targets.size(), sizeof(CCViewData));
  if (!arr) return INTERNAL;
  int n = 0;
  try {
    for (auto& t : targets) {
      float* verts = nullptr; int* idx = nullptr; int vc = 0, ic = 0; int ge = CCGEOM_OK;
      if (ccgeom_tessellate(t.second, deflectionMM, &verts, &vc, &idx, &ic, &ge) != CCGEOM_OK)
        throw CCError(GEOMETRY_FAILED, "GEOMETRY_FAILED",
                      std::string("view failed inside Open CASCADE: ") + ccgeom_last_error());
      CCViewData& d = arr[n];
      d.name = dupStr(t.first);
      d.vertices = verts; d.vertexCount = vc;
      d.indices = idx; d.triangleCount = ic / 3;
      {
        CCGeomFaceRange* ranges = nullptr; int rangeCount = 0; int re = CCGEOM_OK;
        if (ccgeom_face_ranges(t.second, deflectionMM, &ranges, &rangeCount, &re) == CCGEOM_OK) {
          d.faceRanges = (CCFaceRange*)ranges;
          d.faceRangeCount = rangeCount;
        }
      }
      {
        // Census edges for the viewer's edge labels (v0.2.4): same
        // non-fatal-if-absent pattern as face ranges, but the test
        // suites assert presence + census equality on both real
        // backends, so an empty list there fails gates, not silently.
        CCGeomEdge* edges = nullptr; int edgeCount = 0; int ee = CCGEOM_OK;
        if (ccgeom_edge_list(t.second, &edges, &edgeCount, &ee) == CCGEOM_OK) {
          d.edges = (CCViewEdge*)edges;
          d.edgeCount = edgeCount;
        }
      }
      d.volume = s->volumeOf(t.second);
      s->bboxOf(t.second, d.bbox);
      ++n;
    }
  } catch (CCError& e) {
    // Free the partially filled array through the public free function.
    for (int i = 0; i < n; ++i) {
      std::free(arr[i].name);
      ccgeom_free_buffer(arr[i].vertices);
      ccgeom_free_buffer(arr[i].indices);
      ccgeom_free_buffer(arr[i].faceRanges);
      ccgeom_free_buffer(arr[i].edges);
    }
    std::free(arr);
    setLast(s, e);
    return e.code;
  }
  *outObjects = arr; *outCount = n;
  clearLast(s);
  return 0;
}

void cc_free_view_data(CCViewData* objects, int count) {
  if (!objects) return;
  for (int i = 0; i < count; ++i) {
    std::free(objects[i].name);
    ccgeom_free_buffer(objects[i].vertices);
    ccgeom_free_buffer(objects[i].indices);
    ccgeom_free_buffer(objects[i].faceRanges);
    ccgeom_free_buffer(objects[i].edges);
  }
  std::free(objects);
}

int cc_undo(CCSession* s) {
  if (!s) return INTERNAL;
  if (s->undoStack.empty()) {
    CCError e(NOTHING_TO_UNDO, "NOTHING_TO_UNDO", "Nothing to undo.");
    setLast(s, e);
    return e.code;
  }
  s->redoStack.push_back(s->snapshot());
  Snapshot snap = std::move(s->undoStack.back()); s->undoStack.pop_back();
  s->restore(std::move(snap));
  clearLast(s);
  return 0;
}

int cc_redo(CCSession* s) {
  if (!s) return INTERNAL;
  if (s->redoStack.empty()) {
    CCError e(NOTHING_TO_REDO, "NOTHING_TO_REDO", "Nothing to redo.");
    setLast(s, e);
    return e.code;
  }
  s->undoStack.push_back(s->snapshot());
  Snapshot snap = std::move(s->redoStack.back()); s->redoStack.pop_back();
  s->restore(std::move(snap));
  clearLast(s);
  return 0;
}

int cc_history_count(CCSession* s) { return s ? (int)s->history.size() : 0; }

void cc_free_string(char* p) { std::free(p); }

}  // extern "C"
