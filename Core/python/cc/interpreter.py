"""Cascade Console command interpreter.

Language summary (one command per line; ``#`` starts a comment):

    set <var> = <expr>                       parameter / variable
    box <name> <w> <d> <h> [at x,y,z]        primitives: box, cylinder,
    cylinder <name> <r> <h> [at x,y,z]       sphere, cone, torus
    sphere <name> <r> [at x,y,z]
    cone <name> <r1> <r2> <h> [at x,y,z]
    torus <name> <ringR> <tubeR> [at x,y,z]
    profile <name> x,y x,y x,y ...           closed XY polygon (>= 3 pts)
    extrude <name> <profile> <dist>
    union|cut|intersect <name> <a> <b>
    fillet <name> <src> <radius> [edges i,j,...]
    chamfer <name> <src> <dist> [edges i,j,...]
    translate <name> <src> <dx> <dy> <dz>
    rotate <name> <src> <ax> <ay> <az> <angleDeg> [about x,y,z]
    copy <name> <src>        rename <new> <old>      delete <name>
    list                     info <name>             volume <name>
    undo / redo / history
    export step <path> [name]     export stl <path> [name]
    view <path> [name] [deflection]   tessellation JSON for the 3D viewer
    run <scriptfile>                  echo <text...>   help [command]

Any numeric argument may be an expression with no spaces, using numbers,
``$variables``, + - * / % ** and parentheses, e.g. ``box b 2*$w 10 $h/2``.
Names are identifiers ([A-Za-z_][A-Za-z0-9_]*).  Creating a name that
already exists is an error (E1006) — nothing is silently overwritten.
"""

import ast
import json
import math
import os
import re
import shlex
import time

from .errors import (CCError, Codes, arity, bad_expression, duplicate_name,
                     parse_error, undefined_name, unknown_command)
from .geometry import Geometry

_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_MUTATING = {
    "set", "box", "cylinder", "sphere", "cone", "torus", "profile",
    "extrude", "union", "cut", "intersect", "fuse", "common", "fillet",
    "chamfer", "translate", "rotate", "copy", "duplicate", "rename",
    "delete", "clear",
}


class Log:
    """In-memory structured log; optionally mirrored to a file."""

    def __init__(self, path=None):
        self.records = []
        self._fh = open(path, "a", encoding="utf-8") if path else None

    def add(self, level, message, code=None, command=None):
        rec = {"t": round(time.time(), 3), "level": level,
               "message": message, "code": code, "command": command}
        self.records.append(rec)
        if self._fh:
            self._fh.write(json.dumps(rec) + "\n")
            self._fh.flush()
        return rec

    def close(self):
        if self._fh:
            self._fh.close()
            self._fh = None


def tokenize(line):
    """Split one line into tokens. Quoted strings stay one token."""
    try:
        lex = shlex.shlex(line, posix=True)
        lex.whitespace_split = True
        lex.commenters = "#"
        return list(lex)
    except ValueError as exc:
        raise parse_error(f"Could not parse line: {exc}.")


class Interpreter:
    def __init__(self, geometry=None, log=None):
        self.geo = geometry or Geometry()
        self.objects = {}    # name -> TopoDS_Shape (immutable handles)
        self.profiles = {}   # name -> [(x, y), ...]
        self.vars = {}       # name -> float
        self.undo_stack = []  # snapshots taken BEFORE each mutating command
        self.redo_stack = []
        self.history = []     # (line, ok, code) for every executed line
        self.log = log or Log()

    # ------------------------------------------------------------------ utils
    def _snapshot(self):
        return (dict(self.objects), dict(self.profiles), dict(self.vars))

    def _restore(self, snap):
        self.objects, self.profiles, self.vars = (dict(snap[0]), dict(snap[1]),
                                                  dict(snap[2]))

    def _check_name(self, name, kind="object"):
        if not _NAME_RE.match(name):
            raise CCError(Codes.BAD_NAME, "BAD_NAME",
                          f"'{name}' is not a valid {kind} name — use letters, "
                          "digits and underscores, starting with a letter.")

    def _fresh_name(self, name, kind="object"):
        self._check_name(name, kind)
        if name in self.objects or name in self.profiles:
            raise duplicate_name(kind, name)

    def _object(self, name):
        if name not in self.objects:
            raise undefined_name("object", name)
        return self.objects[name]

    def num(self, token):
        """Evaluate a numeric token: literal, $var, or spaceless expression."""
        try:
            tree = ast.parse(token.replace("$", ""), mode="eval")
        except SyntaxError:
            raise bad_expression(token, "not a number or expression")
        return float(self._eval(tree.body, token))

    def _eval(self, node, token):
        if isinstance(node, ast.Constant):
            if isinstance(node.value, (int, float)):
                return float(node.value)
            raise bad_expression(token, "only numbers are allowed")
        if isinstance(node, ast.Name):
            if node.id in self.vars:
                return self.vars[node.id]
            if node.id in ("pi", "e"):
                return math.pi if node.id == "pi" else math.e
            raise bad_expression(token, f"variable '{node.id}' is not set")
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            v = self._eval(node.operand, token)
            return v if isinstance(node.op, ast.UAdd) else -v
        if isinstance(node, ast.BinOp):
            ops = {ast.Add: lambda a, b: a + b, ast.Sub: lambda a, b: a - b,
                   ast.Mult: lambda a, b: a * b, ast.Div: lambda a, b: a / b,
                   ast.Mod: lambda a, b: a % b, ast.Pow: lambda a, b: a ** b}
            fn = ops.get(type(node.op))
            if fn is None:
                raise bad_expression(token, "operator not allowed")
            try:
                return fn(self._eval(node.left, token), self._eval(node.right, token))
            except ZeroDivisionError:
                raise bad_expression(token, "division by zero")
        raise bad_expression(token, "unsupported expression")

    def _point(self, token):
        parts = token.split(",")
        if len(parts) not in (2, 3):
            raise parse_error(f"'{token}' is not a point — write it as x,y or x,y,z.")
        return tuple(self.num(p) for p in parts)

    def _split_as(self, args, cmd):
        """Catalog form support: split '<args...> as <name>'.

        Returns (name, before_tokens) if an 'as' clause is present,
        else (None, args).  The prototype's compact leading-name form
        stays valid; both dialects are documented in DESIGN.md.
        """
        if "as" not in args:
            return None, args
        idx = args.index("as")
        if idx != len(args) - 2:
            raise arity(cmd, "'as <name>' must be the last two words.")
        return args[idx + 1], args[:idx]

    def _placement(self, tokens):
        """Optional trailing 'at x,y,z' — returns the point or None."""
        if not tokens:
            return None
        if len(tokens) == 2 and tokens[0] == "at":
            pt = self._point(tokens[1])
            if len(pt) != 3:
                raise parse_error("'at' needs a 3D point: at x,y,z.")
            return pt
        raise arity("placement", "expected 'at x,y,z' at the end of the command.")

    def _place(self, shape, at):
        if at is None or at == (0.0, 0.0, 0.0):
            return shape
        return self.geo.translate(shape, at[0], at[1], at[2])

    # -------------------------------------------------------------- execution
    def execute(self, line, source=None, line_no=None):
        """Execute one line. Returns a result string ('' for blank/comment).

        Raises CCError on any failure; the failure is logged either way.
        """
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            return ""
        try:
            tokens = tokenize(line)
            if not tokens:
                return ""
            result = self._dispatch(tokens, line)
        except CCError as err:
            if err.line_no is None:
                err.line_no, err.source = line_no, source
            self.history.append((stripped, False, err.code))
            self.log.add("error", err.message, code=err.code, command=stripped)
            raise
        except Exception as exc:  # our bug — still structured, still logged
            err = CCError(Codes.INTERNAL, "INTERNAL",
                          f"Internal error: {exc.__class__.__name__}: {exc}",
                          line_no=line_no, source=source)
            self.history.append((stripped, False, err.code))
            self.log.add("error", err.message, code=err.code, command=stripped)
            raise err
        self.history.append((stripped, True, None))
        self.log.add("info", result or "ok", command=stripped)
        return result

    def _dispatch(self, tokens, line):
        cmd, args = tokens[0].lower(), tokens[1:]
        handler = getattr(self, f"cmd_{cmd.replace('-', '_')}", None)
        if handler is None:
            raise unknown_command(tokens[0])
        if cmd in _MUTATING:
            # Snapshot BEFORE mutation; a failed command must not leave a
            # bogus undo step, so pop it again if the handler raises.
            self.undo_stack.append(self._snapshot())
            self.redo_stack.clear()
            try:
                return handler(args)
            except Exception:
                self.undo_stack.pop()
                raise
        return handler(args)

    def run_script(self, path):
        """Execute a .txt/.ccs script file, line by line. Stops at the
        first failing line and reports it with its line number."""
        if not os.path.isfile(path):
            raise CCError(Codes.FILE_NOT_FOUND, "FILE_NOT_FOUND",
                          f"Script file '{path}' does not exist.")
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.readlines()
        except OSError as exc:
            raise CCError(Codes.FILE_READ, "FILE_READ",
                          f"Could not read script '{path}': {exc}")
        done = 0
        for i, raw in enumerate(lines, start=1):
            if not raw.strip() or raw.strip().startswith("#"):
                continue
            try:
                self.execute(raw, source=path, line_no=i)
            except CCError as err:
                raise CCError(Codes.SCRIPT_FAILED, "SCRIPT_FAILED",
                              f"Script stopped: line {i} failed — {err.message}",
                              line_no=i, source=path)
            done += 1
        return f"Ran {done} command(s) from {path}."

    # --------------------------------------------------------------- commands
    def cmd_help(self, args):
        if args:
            name = args[0].lower()
            for line in HELP_LINES:
                if line.startswith(name + " "):
                    return line
            raise unknown_command(args[0])
        return "Commands:\n" + "\n".join(HELP_LINES)

    def cmd_echo(self, args):
        return " ".join(args)

    def cmd_set(self, args):
        if len(args) != 3 or args[1] != "=":
            raise arity("set", "write: set <var> = <expr>")
        self._check_name(args[0], "variable")
        self.vars[args[0]] = self.num(args[2])
        return f"{args[0]} = {self.vars[args[0]]}"

    def cmd_clear(self, args):
        self.objects.clear(); self.profiles.clear()
        return "Cleared all objects and profiles (variables kept)."

    # primitives -------------------------------------------------------------
    def _primitive(self, cmd, args, n_nums, make):
        as_name, before = self._split_as(args, cmd)
        if as_name is not None:  # catalog form: box <nums> [at x,y,z] as <name>
            name, num_tokens, rest = as_name, before[:n_nums], before[n_nums:]
            if len(num_tokens) != n_nums:
                raise arity(cmd, f"write: {cmd} <{n_nums} number(s)> [at x,y,z] as <name>")
        else:                    # compact form: box <name> <nums> [at x,y,z]
            if len(args) < 1 + n_nums:
                raise arity(cmd, f"write: {cmd} <name> <{n_nums} number(s)> [at x,y,z]")
            name, num_tokens, rest = args[0], args[1:1 + n_nums], args[1 + n_nums:]
        self._fresh_name(name)
        nums = [self.num(t) for t in num_tokens]
        at = self._placement(rest)
        self.objects[name] = self._place(make(*nums), at)
        return f"Created {name}."

    def cmd_box(self, args):
        return self._primitive("box", args, 3, self.geo.box)

    def cmd_cylinder(self, args):
        return self._primitive("cylinder", args, 2, self.geo.cylinder)

    def cmd_sphere(self, args):
        return self._primitive("sphere", args, 1, self.geo.sphere)

    def cmd_cone(self, args):
        return self._primitive("cone", args, 3, self.geo.cone)

    def cmd_torus(self, args):
        return self._primitive("torus", args, 2, self.geo.torus)

    # profile / extrude ---------------------------------------------------------
    def cmd_profile(self, args):
        if len(args) < 4:
            raise arity("profile", "write: profile <name> x,y x,y x,y [...]")
        name = args[0]
        self._fresh_name(name, "profile")
        pts = []
        for tok in args[1:]:
            pt = self._point(tok)
            if len(pt) != 2:
                raise parse_error(f"Profile point '{tok}' must be 2D (x,y).")
            pts.append(pt)
        if len(pts) < 3:
            raise CCError(Codes.BAD_PROFILE, "BAD_PROFILE",
                          "A profile needs at least 3 points.")
        self.profiles[name] = pts
        return f"Profile {name}: {len(pts)} points."

    def cmd_extrude(self, args):
        as_name, before = self._split_as(args, "extrude")
        if as_name is not None:  # extrude <profile> <dist> as <name>
            if len(before) != 2:
                raise arity("extrude", "write: extrude <profile> <dist> as <name>")
            name, prof, dist = as_name, before[0], before[1]
        else:
            if len(args) != 3:
                raise arity("extrude", "write: extrude <name> <profile> <dist>")
            name, prof, dist = args
        self._fresh_name(name)
        if prof not in self.profiles:
            raise undefined_name("profile", prof)
        self.objects[name] = self.geo.extrude(self.profiles[prof],
                                              self.num(dist))
        return f"Created {name}."

    # booleans ------------------------------------------------------------------
    def _boolean_cmd(self, cmd, args, fn):
        as_name, before = self._split_as(args, cmd)
        before = [t for t in before if t != "minus"]  # catalog: cut a minus b
        if as_name is not None:  # catalog form: union <a> <b> as <name>
            if len(before) != 2:
                raise arity(cmd, f"write: {cmd} <a> <b> as <name>")
            name, a, b = as_name, before[0], before[1]
        else:
            if len(args) != 3:
                raise arity(cmd, f"write: {cmd} <name> <a> <b>")
            name, a, b = args
        # Catalog convention: 'as <name>' may reuse an OPERAND's name
        # (in-place update, e.g. 'fuse body1 boss1 as body1'); reusing
        # any other existing name is still E1006.
        if as_name is not None and name in (a, b):
            self._check_name(name)
        else:
            self._fresh_name(name)
        self.objects[name] = fn(self._object(a), self._object(b))
        return f"Created {name}."

    def cmd_union(self, args):
        return self._boolean_cmd("union", args, self.geo.union)

    def cmd_fuse(self, args):  # catalog alias of union
        return self._boolean_cmd("fuse", args, self.geo.union)

    def cmd_cut(self, args):
        return self._boolean_cmd("cut", args, self.geo.cut)

    def cmd_intersect(self, args):
        return self._boolean_cmd("intersect", args, self.geo.intersect)

    def cmd_common(self, args):  # catalog alias of intersect
        return self._boolean_cmd("common", args, self.geo.intersect)

    # finishing -------------------------------------------------------------------
    def _finish_cmd(self, cmd, args, fn):
        as_name, before = self._split_as(args, cmd)
        if as_name is not None:  # catalog form: fillet <src> <size> [edges ..] as <name>
            name, src, size_tok = as_name, before[0], before[1] if len(before) > 1 else None
            rest = before[2:]
            if size_tok is None:
                raise arity(cmd, f"write: {cmd} <src> <size> [edges i,j,...] as <name>")
            if name in self.objects and name != src:
                raise duplicate_name("object", name)
            self._check_name(name)
            indices = self._edge_list(rest, cmd)
            self.objects[name] = fn(self._object(src), self.num(size_tok), indices)
            return f"Created {name}."
        if len(args) not in (3, 5):
            raise arity(cmd, f"write: {cmd} <name> <src> <size> [edges i,j,...]")
        self._fresh_name(args[0])
        indices = self._edge_list(args[3:], cmd)
        self.objects[args[0]] = fn(self._object(args[1]), self.num(args[2]), indices)
        return f"Created {args[0]}."

    @staticmethod
    def _edge_list(tokens, cmd):
        if not tokens:
            return None
        if len(tokens) == 2 and tokens[0] == "edges":
            try:
                return [int(t) for t in tokens[1].split(",")]
            except ValueError:
                raise parse_error(f"'{tokens[1]}' is not a list of edge numbers.")
        raise arity(cmd, "expected 'edges i,j,...'.")

    def cmd_fillet(self, args):
        return self._finish_cmd("fillet", args, self.geo.fillet)

    def cmd_chamfer(self, args):
        return self._finish_cmd("chamfer", args, self.geo.chamfer)

    # transforms --------------------------------------------------------------------
    def cmd_translate(self, args):
        as_name, before = self._split_as(args, "translate")
        if as_name is not None:  # translate <src> <dx> <dy> <dz> as <name>
            if len(before) != 4:
                raise arity("translate", "write: translate <src> <dx> <dy> <dz> as <name>")
            name, src, deltas = as_name, before[0], before[1:4]
        else:
            if len(args) != 5:
                raise arity("translate", "write: translate <name> <src> <dx> <dy> <dz>")
            name, src, deltas = args[0], args[1], args[2:5]
        self._fresh_name(name)
        dx, dy, dz = (self.num(t) for t in deltas)
        self.objects[name] = self.geo.translate(self._object(src), dx, dy, dz)
        return f"Created {name}."

    def cmd_rotate(self, args):
        as_name, before = self._split_as(args, "rotate")
        if as_name is not None:  # rotate <src> <ax> <ay> <az> <deg> [about ..] as <name>
            name, work = as_name, before
            if len(work) not in (5, 7):
                raise arity("rotate", "write: rotate <src> <ax> <ay> <az> "
                                      "<angleDeg> [about x,y,z] as <name>")
            src, axis_toks, angle_tok, tail = work[0], work[1:4], work[4], work[5:]
        else:
            if len(args) not in (6, 8):
                raise arity("rotate", "write: rotate <name> <src> <ax> <ay> <az> "
                                      "<angleDeg> [about x,y,z]")
            name, src = args[0], args[1]
            axis_toks, angle_tok, tail = args[2:5], args[5], args[6:]
        self._fresh_name(name)
        axis = tuple(self.num(t) for t in axis_toks)
        angle = self.num(angle_tok)
        centre = (0.0, 0.0, 0.0)
        if tail:
            if len(tail) != 2 or tail[0] != "about":
                raise arity("rotate", "expected 'about x,y,z'.")
            centre = self._point(tail[1])
            if len(centre) != 3:
                raise parse_error("'about' needs a 3D point: about x,y,z.")
        self.objects[name] = self.geo.rotate(self._object(src), axis,
                                             angle, centre)
        return f"Created {name}."

    # object management --------------------------------------------------------------
    def cmd_copy(self, args):
        if len(args) != 2:
            raise arity("copy", "write: copy <newName> <src>")
        self._fresh_name(args[0])
        self.objects[args[0]] = self._object(args[1])  # shapes are immutable
        return f"Copied {args[1]} to {args[0]}."

    def cmd_duplicate(self, args):  # catalog form: duplicate <src> as <new>
        as_name, before = self._split_as(args, "duplicate")
        if as_name is None or len(before) != 1:
            raise arity("duplicate", "write: duplicate <src> as <newName>")
        self._fresh_name(as_name)
        self.objects[as_name] = self._object(before[0])
        return f"Copied {before[0]} to {as_name}."

    def cmd_rename(self, args):
        as_name, before = self._split_as(args, "rename")
        if as_name is not None:  # catalog form: rename <old> as <new>
            if len(before) != 1:
                raise arity("rename", "write: rename <oldName> as <newName>")
            new, old = as_name, before[0]
        else:
            if len(args) != 2:
                raise arity("rename", "write: rename <newName> <oldName>")
            new, old = args
        self._fresh_name(new)
        shape = self._object(old)
        del self.objects[old]
        self.objects[new] = shape
        return f"Renamed {old} to {new}."

    def cmd_delete(self, args):
        if len(args) != 1:
            raise arity("delete", "write: delete <name>")
        if args[0] in self.objects:
            del self.objects[args[0]]
        elif args[0] in self.profiles:
            del self.profiles[args[0]]
        else:
            raise undefined_name("object or profile", args[0])
        return f"Deleted {args[0]}."

    def cmd_list(self, args):
        lines = []
        for name in sorted(self.objects):
            lines.append(f"object  {name}: volume {self.geo.volume(self.objects[name]):.3f} mm^3")
        for name in sorted(self.profiles):
            lines.append(f"profile {name}: {len(self.profiles[name])} points")
        for name in sorted(self.vars):
            lines.append(f"var     {name} = {self.vars[name]}")
        return "\n".join(lines) if lines else "Nothing defined yet."

    def cmd_info(self, args):
        if len(args) != 1:
            raise arity("info", "write: info <name>")
        shape = self._object(args[0])
        bb = self.geo.bbox(shape)
        faces, edges = self.geo.counts(shape)
        return (f"{args[0]}: volume {self.geo.volume(shape):.3f} mm^3, "
                f"area {self.geo.area(shape):.3f} mm^2, faces {faces}, edges {edges}, "
                f"bbox ({bb[0]:.3f},{bb[1]:.3f},{bb[2]:.3f})..({bb[3]:.3f},{bb[4]:.3f},{bb[5]:.3f})")

    def cmd_volume(self, args):
        if len(args) != 1:
            raise arity("volume", "write: volume <name>")
        return f"{args[0]} volume = {self.geo.volume(self._object(args[0])):.6f} mm^3"

    def cmd_measure_volume(self, args):  # catalog alias of volume
        return self.cmd_volume(args)

    def cmd_show_vars(self, args):
        if not self.vars:
            return "No variables set."
        return "\n".join(f"{k} = {v}" for k, v in sorted(self.vars.items()))

    # history ---------------------------------------------------------------------------
    def cmd_undo(self, args):
        if not self.undo_stack:
            raise CCError(Codes.NOTHING_TO_UNDO, "NOTHING_TO_UNDO",
                          "Nothing to undo.")
        self.redo_stack.append(self._snapshot())
        self._restore(self.undo_stack.pop())
        return "Undid last command."

    def cmd_redo(self, args):
        if not self.redo_stack:
            raise CCError(Codes.NOTHING_TO_REDO, "NOTHING_TO_REDO",
                          "Nothing to redo.")
        self.undo_stack.append(self._snapshot())
        self._restore(self.redo_stack.pop())
        return "Redid command."

    def cmd_history(self, args):
        if not self.history:
            return "No commands yet."
        out = []
        for i, (line, ok, code) in enumerate(self.history, 1):
            out.append(f"{i}. {'ok  ' if ok else f'E{code}'}  {line}")
        return "\n".join(out)

    def cmd_shape_history(self, args):
        # Integration resolution (a): `history` is the command log above;
        # the OCCT BRepTools_History query is `shape-history <name>`.
        # The prototype does not record BRepTools_History, so this fails
        # loudly instead of pretending — NOT_IMPLEMENTED (E5002).
        raise CCError(Codes.NOT_IMPLEMENTED, "NOT_IMPLEMENTED",
                      "shape-history is not implemented in the Python "
                      "prototype (BRepTools_History is not recorded); it "
                      "is facade-ready in the C++ session layer.")

    # files --------------------------------------------------------------------------------
    def cmd_run(self, args):
        if len(args) != 1:
            raise arity("run", "write: run <scriptfile>")
        return self.run_script(args[0])

    def cmd_export(self, args):
        if len(args) not in (2, 3):
            raise arity("export", "write: export step|stl <path> [name]")
        kind = args[0].lower()
        if kind not in ("step", "stl"):
            raise arity("export", "first argument must be 'step' or 'stl'.")
        if len(args) == 3:
            targets = [(args[2], self._object(args[2]))]
        else:
            if not self.objects:
                raise CCError(Codes.UNDEFINED_NAME, "UNDEFINED_NAME",
                              "No objects to export yet.")
            targets = sorted(self.objects.items())
        # One shape per file for this prototype: with several objects and no
        # name argument, export each to <base>_<name>.<ext>.
        written = []
        for name, shape in targets:
            path = args[1]
            if len(targets) > 1:
                root, ext = os.path.splitext(path)
                path = f"{root}_{name}{ext}"
            if kind == "step":
                self.geo.export_step(shape, path)
            else:
                self.geo.export_stl(shape, path)
            written.append(path)
        return "Exported: " + ", ".join(written)

    # Canonical catalog export forms (integration resolution (b)):
    # export-step <shape> <file> / export-stl <shape> <file>.
    # The prototype's compact `export step|stl <path> [name]` stays as
    # an accepted alias (cmd_export above).
    def cmd_export_step(self, args):
        if len(args) != 2:
            raise arity("export-step", "write: export-step <shape> <file>")
        self.geo.export_step(self._object(args[0]), args[1])
        return f"Exported {args[0]} to {args[1]}."

    def cmd_export_stl(self, args):
        if len(args) != 2:
            raise arity("export-stl", "write: export-stl <shape> <file>")
        self.geo.export_stl(self._object(args[0]), args[1])
        return f"Exported {args[0]} to {args[1]}."

    def cmd_view(self, args):
        if len(args) not in (1, 2, 3):
            raise arity("view", "write: view <path.json> [name] [deflection]")
        if len(args) >= 2:
            targets = [(args[1], self._object(args[1]))]
        else:
            targets = sorted(self.objects.items())
        if not targets:
            raise CCError(Codes.UNDEFINED_NAME, "UNDEFINED_NAME",
                          "No objects to show yet.")
        deflection = self.num(args[2]) if len(args) == 3 else 0.5
        objs = []
        for name, shape in targets:
            verts, idx = self.geo.tessellate(shape, deflection)
            objs.append({"name": name, "vertices": verts, "indices": idx,
                         "triangleCount": len(idx) // 3,
                         "volume": self.geo.volume(shape),
                         "bbox": list(self.geo.bbox(shape))})
        doc = {"format": "cascade-console-view", "version": 1,
               "units": "mm", "objects": objs}
        try:
            with open(args[0], "w", encoding="utf-8") as fh:
                json.dump(doc, fh)
        except OSError as exc:
            raise CCError(Codes.EXPORT_FAILED, "EXPORT_FAILED",
                          f"Could not write view data to '{args[0]}': {exc}")
        total = sum(o["triangleCount"] for o in objs)
        return f"View data written to {args[0]}: {len(objs)} object(s), {total} triangles."


HELP_LINES = [
    "set <var> = <expr> — define a parameter usable as $var in numbers",
    "box <name> <w> <d> <h> [at x,y,z] — axis-aligned box from the origin corner",
    "cylinder <name> <r> <h> [at x,y,z] — cylinder, base on XY, axis +Z",
    "sphere <name> <r> [at x,y,z] — sphere centred on the origin",
    "cone <name> <r1> <r2> <h> [at x,y,z] — cone/frustum, base r1 at z=0",
    "torus <name> <ringR> <tubeR> [at x,y,z] — torus in the XY plane",
    "profile <name> x,y x,y x,y ... — closed 2D polygon profile",
    "extrude <name> <profile> <dist> — extrude a profile along +Z",
    "union <name> <a> <b> — fuse two solids (catalog: fuse <a> <b> as <name>)",
    "cut <name> <a> <b> — subtract b from a (catalog: cut <a> minus <b> as <name>)",
    "intersect <name> <a> <b> — common volume (catalog: common <a> <b> as <name>)",
    "fillet <name> <src> <radius> [edges i,j,...] — round edges (default: all)",
    "chamfer <name> <src> <dist> [edges i,j,...] — chamfer edges (default: all)",
    "translate <name> <src> <dx> <dy> <dz> — moved copy of src",
    "rotate <name> <src> <ax> <ay> <az> <deg> [about x,y,z] — rotated copy",
    "copy <name> <src> / rename <new> <old> / delete <name> / clear",
    "list / info <name> / volume <name> — inspect the model",
    "undo / redo / history — command history",
    "export step|stl <path> [name] — write CAD/mesh files",
    "view <path.json> [name] [deflection] — tessellation data for the 3D viewer",
    "run <scriptfile> — execute a .txt/.ccs script of commands",
    "echo <text...> / help [command]",
]
