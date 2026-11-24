//
//  SimForm.swift
//  Cascade Console - Model
//
//  The Simulation form's state and its command builder (v0.3.2).
//
//  The form does not implement any simulation: it GENERATES the
//  existing `sim ...` console commands, verbatim, and the app runs
//  them through the same pipeline a typed line takes (so the
//  results land in the console log, from the real solver). The
//  statics flow is fully form-expressible:
//
//    sim material <object> <name>          (library picker below)
//    sim fix <object> @face <n>            (clamped face)
//    sim load <object> @face <n> force <fx> <fy> <fz>
//    sim load <object> @face <n> pressure <MPa>
//    sim mesh size <mm>
//    sim static                            (statics mode)
//    sim run <object>
//
//  Thermal stays console-only: its boundary conditions (held
//  temperatures, heat flux, convection) are a second form family,
//  and a half-modelled thermal form would be worse than the
//  console it replaces. Face numbers are the viewer's census
//  indices — the View panel's face labels show them on the model.
//

import Foundation

public struct SimFormState: Equatable {
    /// The engine's material library (ccsim.cpp materialLibrary()).
    /// Pinned both ways in CI: the per-command matrix asserts each
    /// of these names appears in `sim material list` output on the
    /// mc backend, and the Swift harness asserts this list.
    public static let materials = [
        "steel", "stainless-304", "aluminium-6061", "aluminium-7075",
        "titanium-6al4v", "brass", "copper", "pla", "abs", "petg",
    ]
    /// The engine's own default (`sim mesh size` never issued).
    public static let defaultMeshSize = "2.5"

    public enum LoadKind: String, Equatable, CaseIterable {
        case force, pressure
    }

    public var material: String = "steel"
    public var fixedFace: String = "0"
    public var loadFace: String = "1"
    public var loadKind: LoadKind = .force
    public var forceX: String = "0"
    public var forceY: String = "0"
    public var forceZ: String = "-100"
    public var pressureMPa: String = "1"
    public var meshSize: String = SimFormState.defaultMeshSize

    public init() {}
}

public enum SimScriptBuilder {
    /// The setup lines for one part, in dependency order, or nil
    /// when any field fails validation (the form disables its
    /// buttons then — a half-valid setup is never sent).
    public static func setupLines(object qualified: String,
                                  form: SimFormState) -> [String]? {
        guard SimFormState.materials.contains(form.material),
              let fixed = faceIndex(form.fixedFace),
              let load = faceIndex(form.loadFace),
              let mesh = number(form.meshSize), mesh > 0
        else { return nil }
        var lines = [
            "sim material \(qualified) \(form.material)",
            "sim fix \(qualified) @face \(fixed)",
        ]
        switch form.loadKind {
        case .force:
            guard let fx = number(form.forceX),
                  let fy = number(form.forceY),
                  let fz = number(form.forceZ)
            else { return nil }
            lines.append("sim load \(qualified) @face \(load) force "
                + "\(fmt(fx)) \(fmt(fy)) \(fmt(fz))")
        case .pressure:
            guard let p = number(form.pressureMPa) else { return nil }
            lines.append("sim load \(qualified) @face \(load) pressure \(fmt(p))")
        }
        lines.append("sim mesh size \(fmt(mesh))")
        lines.append("sim static")
        return lines
    }

    public static func runLine(object qualified: String) -> String {
        "sim run \(qualified)"
    }

    public static func clearLine(object qualified: String) -> String {
        "sim clear \(qualified)"
    }

    // MARK: Field parsing (same acceptance as the engine's own
    // number parsing: a plain decimal number; face indices must
    // additionally be whole and non-negative).

    public static func faceIndex(_ text: String) -> Int? {
        guard let v = number(text), v >= 0,
              v == v.rounded(), v < 1e9 else { return nil }
        return Int(v)
    }

    public static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    /// Format like the step-line builder does, so generated lines
    /// read the same as panel-built model commands.
    private static func fmt(_ v: Double) -> String {
        StepLineBuilder.formatNumber(String(format: "%.6g", v)) ?? "0"
    }
}
