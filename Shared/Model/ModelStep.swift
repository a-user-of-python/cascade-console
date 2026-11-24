import Foundation

// MARK: - Parametric history steps (v0.3.0)
//
// A model is an ordered list of STEPS. Each step is one command plus
// its parameter values plus its result name. Creating from the UI
// appends a step and executes it; EDITING a step (or deleting one)
// rebuilds the model by replaying the whole list into a fresh
// session (see ReplayBuilder + AppState.replayProject). A step whose
// command is "script" is a legacy import: the verbatim text of a
// pre-v0.3.0 .cascade script, replayed through the script runner.
//
// Object-reference parameters store QUALIFIED names ("box:part") —
// the values the part-tree pickers hand out — so a step always points
// at the exact object it was created against, and a replay failure
// (a referenced object no longer exists because an earlier step was
// edited or deleted) is reported against the step that references
// it, never silently absorbed.

public struct ModelStep: Codable, Identifiable, Equatable {
    public var id: UUID
    /// CommandSpec id, or "script" for a legacy script import.
    public var command: String
    /// Parameter values as strings, keyed by ParamSpec.key. Object
    /// references are qualified names.
    public var params: [String: String]
    /// Result name as entered in the form; "" means auto-assign.
    public var name: String
    /// The qualified name the engine actually assigned, learned from
    /// the session after execution (post-suffix truth). Nil until the
    /// step has executed successfully at least once.
    public var assignedName: String?
    /// Verbatim script text for command == "script".
    public var scriptText: String?

    public init(id: UUID = UUID(), command: String,
                params: [String: String] = [:], name: String = "",
                assignedName: String? = nil, scriptText: String? = nil) {
        self.id = id
        self.command = command
        self.params = params
        self.name = name
        self.assignedName = assignedName
        self.scriptText = scriptText
    }

    public var isScript: Bool { command == "script" }

    /// One-line label for the History list: "Cut 'part'".
    public var displayTitle: String {
        if isScript { return "Imported script" }
        let title = CommandCatalog.spec(for: command)?.title ?? command
        let shown = assignedName.map { CascadeNames.display(of: $0) }
            ?? (name.isEmpty ? nil : name)
        if let shown { return "\(title) '\(shown)'" }
        return title
    }

    private enum CodingKeys: String, CodingKey {
        case id, command, params, name, assignedName, scriptText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        command = try c.decode(String.self, forKey: .command)
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        assignedName = try c.decodeIfPresent(String.self, forKey: .assignedName)
        scriptText = try c.decodeIfPresent(String.self, forKey: .scriptText)
    }
}

// MARK: - Step -> command line

public enum StepLineBuilder {

    /// Canonical number rendering for the interpreter: integral
    /// values without a decimal point ("10"), everything else in
    /// Swift's shortest round-trip form ("2.5"). Nil when the string
    /// is not a number — the caller reports the step as invalid
    /// instead of sending the engine a line it must reject.
    public static func formatNumber(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let v = Double(trimmed), v.isFinite else { return nil }
        if v == v.rounded() && abs(v) < 1e15 {
            return String(Int(v))
        }
        return String(v)
    }

    /// The interpreter line for one step, with the result display
    /// name already resolved (auto-name / suffix applied by the
    /// caller — ReplayBuilder). Nil when a required parameter is
    /// missing or non-numeric.
    public static func line(for step: ModelStep, resultDisplayName: String) -> String? {
        let p = step.params
        func num(_ key: String) -> String? {
            guard let raw = p[key] else { return nil }
            return formatNumber(raw)
        }
        func ref(_ key: String) -> String? {
            let raw = (p[key] ?? "").trimmingCharacters(in: .whitespaces)
            return raw.isEmpty ? nil : raw
        }
        func atSuffix() -> String? {
            guard let x = num("atX"), let y = num("atY"), let z = num("atZ") else { return nil }
            if x == "0" && y == "0" && z == "0" { return "" }
            return " at \(x),\(y),\(z)"
        }
        let name = resultDisplayName
        switch step.command {
        case "box":
            guard let w = num("width"), let d = num("depth"), let h = num("height"),
                  let at = atSuffix() else { return nil }
            return "box \(name) \(w) \(d) \(h)\(at)"
        case "cylinder":
            guard let r = num("radius"), let h = num("height"),
                  let at = atSuffix() else { return nil }
            return "cylinder \(name) \(r) \(h)\(at)"
        case "sphere":
            guard let r = num("radius"), let at = atSuffix() else { return nil }
            return "sphere \(name) \(r)\(at)"
        case "cone":
            guard let r1 = num("radius1"), let r2 = num("radius2"), let h = num("height"),
                  let at = atSuffix() else { return nil }
            return "cone \(name) \(r1) \(r2) \(h)\(at)"
        case "torus":
            guard let ring = num("ringRadius"), let tube = num("tubeRadius"),
                  let at = atSuffix() else { return nil }
            return "torus \(name) \(ring) \(tube)\(at)"
        case "profile":
            let points = (p["points"] ?? "")
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                .joined(separator: " ")
            guard !points.isEmpty else { return nil }
            return "profile \(name) \(points)"
        case "extrude":
            guard let prof = ref("profile"), let dist = num("distance") else { return nil }
            return "extrude \(name) \(prof) \(dist)"
        case "union", "cut", "intersect":
            guard let a = ref("a"), let b = ref("b") else { return nil }
            return "\(step.command) \(name) \(a) \(b)"
        case "fillet", "chamfer":
            let sizeKey = step.command == "fillet" ? "radius" : "distance"
            guard let src = ref("source"), let size = num(sizeKey) else { return nil }
            var line = "\(step.command) \(name) \(src) \(size)"
            let edges = (p["edges"] ?? "").trimmingCharacters(in: .whitespaces)
            if !edges.isEmpty { line += " edges \(edges)" }
            return line
        case "translate":
            guard let src = ref("source"), let dx = num("dx"), let dy = num("dy"),
                  let dz = num("dz") else { return nil }
            return "translate \(name) \(src) \(dx) \(dy) \(dz)"
        case "rotate":
            guard let src = ref("source"), let ax = num("axisX"), let ay = num("axisY"),
                  let az = num("axisZ"), let angle = num("angle"),
                  let bx = num("aboutX"), let by = num("aboutY"), let bz = num("aboutZ")
            else { return nil }
            var line = "rotate \(name) \(src) \(ax) \(ay) \(az) \(angle)"
            if bx != "0" || by != "0" || bz != "0" {
                line += " about \(bx),\(by),\(bz)"
            }
            return line
        case "copy":
            guard let src = ref("source") else { return nil }
            return "copy \(name) \(src)"
        default:
            return nil
        }
    }
}

// MARK: - Replay builder

/// One step after the replay build: the line to execute (nil for
/// script steps and for steps whose parameters don't build), the
/// qualified name the step is predicted to receive, and the build
/// error when the line could not be produced.
public struct BuiltStep: Equatable {
    public var step: ModelStep
    public var line: String?
    public var predictedName: String?
    public var buildError: String?
}

public enum ReplayBuilder {

    /// Walk the step list maintaining the running name set exactly
    /// the way the engine does (per-directory claim with the shared
    /// suffix rule), so every produced line already carries its final
    /// result name and the engine's own claim finds it free. Operand
    /// references inside params are already qualified (picker-stored)
    /// and pass through untouched.
    ///
    /// `initialNames` seeds the set for predicting a single new step
    /// against a live session; a full replay passes [].
    public static func build(steps: [ModelStep],
                             initialNames: [String] = []) -> [BuiltStep] {
        var existing = initialNames
        var out: [BuiltStep] = []
        for step in steps {
            if step.isScript {
                out.append(BuiltStep(step: step, line: nil,
                                     predictedName: nil, buildError: nil))
                continue
            }
            guard let spec = CommandCatalog.spec(for: step.command) else {
                out.append(BuiltStep(step: step, line: nil, predictedName: nil,
                                     buildError: "Unknown command '\(step.command)'."))
                continue
            }
            let requested = step.name.isEmpty
                ? CascadeNames.autoName(directory: spec.directory, existing: existing)
                : step.name
            let finalDisplay = CascadeNames.uniqueName(
                directory: spec.directory, requested: requested, existing: existing)
            let qualified = CascadeNames.qualify(directory: spec.directory,
                                                 display: finalDisplay)
            guard let line = StepLineBuilder.line(for: step,
                                                  resultDisplayName: finalDisplay) else {
                out.append(BuiltStep(step: step, line: nil, predictedName: qualified,
                                     buildError: "Step '\(step.displayTitle)' has a missing or non-numeric parameter."))
                continue
            }
            existing.append(qualified)
            out.append(BuiltStep(step: step, line: line,
                                 predictedName: qualified, buildError: nil))
        }
        return out
    }
}
