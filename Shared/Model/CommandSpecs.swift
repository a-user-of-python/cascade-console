import Foundation

// MARK: - UI command catalog + parameter specs (v0.3.0)
//
// The right sidebar's "big list of commands" is generated from these
// specs, and each command's parameter form (sliders + inputs) is
// generated from its [ParamSpec]. ONLY commands the native
// interpreter actually implements appear here — the ship rule: a
// command that can't pass is out of the advertised list. The
// interpreter's remaining surface (set / list / info / volume /
// undo / redo / history / export / run / echo / help / sim and the
// view commands) is not step-shaped; it stays available in the
// console and in scripts, and the view commands keep their viewer
// controls. shape-history answers E5002 by design and is NOT listed.
//
// Parameter values are stored as strings in a step (exactly as the
// user typed or the slider set them); StepLineBuilder renders them
// into the interpreter's compact grammar. Object references are
// stored as QUALIFIED names ("box:part") handed out by the pickers,
// so replay never depends on bare-name resolution luck.
//
// Slider ranges are deliberately generous (a slider is a convenience,
// the paired numeric field always wins and may go past the range).

public enum ParamType: String, Equatable {
    case length     // mm, slider + field
    case number     // unitless, slider + field
    case angle      // degrees, slider + field
    case text       // free text field
    case objectRef  // picker over session objects (qualified names)
    case profileRef // picker over session profiles (qualified names)
    case pointList  // "x,y x,y ..." text
    case edgeList   // "" (all edges) or "0,2,5"
}

public struct ParamSpec: Equatable {
    public var key: String
    public var label: String
    public var type: ParamType
    public var defaultValue: String
    public var sliderMin: Double?
    public var sliderMax: Double?

    public init(key: String, label: String, type: ParamType,
                defaultValue: String,
                sliderMin: Double? = nil, sliderMax: Double? = nil) {
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.sliderMin = sliderMin
        self.sliderMax = sliderMax
    }

    public var hasSlider: Bool { sliderMin != nil && sliderMax != nil }
}

public struct CommandSpec: Equatable {
    /// The interpreter verb; also the name directory the result
    /// lands in (UI commands have no aliases, so verb == directory).
    public var id: String
    public var title: String
    public var group: String
    public var summary: String
    public var params: [ParamSpec]

    public var directory: String { id }

    public func param(_ key: String) -> ParamSpec? {
        params.first { $0.key == key }
    }

    /// Default parameter values for a fresh form.
    public var defaultParams: [String: String] {
        Dictionary(uniqueKeysWithValues: params.map { ($0.key, $0.defaultValue) })
    }
}

public enum CommandCatalog {

    private static func atParams() -> [ParamSpec] {
        [ParamSpec(key: "atX", label: "At X", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
         ParamSpec(key: "atY", label: "At Y", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
         ParamSpec(key: "atZ", label: "At Z", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500)]
    }

    public static let all: [CommandSpec] = [
        CommandSpec(id: "box", title: "Box", group: "Primitives",
                    summary: "Axis-aligned box from the origin corner.",
                    params: [
                        ParamSpec(key: "width", label: "Width", type: .length, defaultValue: "10", sliderMin: 0.1, sliderMax: 500),
                        ParamSpec(key: "depth", label: "Depth", type: .length, defaultValue: "10", sliderMin: 0.1, sliderMax: 500),
                        ParamSpec(key: "height", label: "Height", type: .length, defaultValue: "10", sliderMin: 0.1, sliderMax: 500),
                    ] + atParams()),
        CommandSpec(id: "cylinder", title: "Cylinder", group: "Primitives",
                    summary: "Cylinder, base on XY, axis +Z.",
                    params: [
                        ParamSpec(key: "radius", label: "Radius", type: .length, defaultValue: "5", sliderMin: 0.05, sliderMax: 250),
                        ParamSpec(key: "height", label: "Height", type: .length, defaultValue: "10", sliderMin: 0.1, sliderMax: 500),
                    ] + atParams()),
        CommandSpec(id: "sphere", title: "Sphere", group: "Primitives",
                    summary: "Sphere centred on the origin.",
                    params: [
                        ParamSpec(key: "radius", label: "Radius", type: .length, defaultValue: "5", sliderMin: 0.05, sliderMax: 250),
                    ] + atParams()),
        CommandSpec(id: "cone", title: "Cone", group: "Primitives",
                    summary: "Cone / frustum, base radius at z=0.",
                    params: [
                        ParamSpec(key: "radius1", label: "Base radius", type: .length, defaultValue: "5", sliderMin: 0.05, sliderMax: 250),
                        ParamSpec(key: "radius2", label: "Top radius", type: .length, defaultValue: "2", sliderMin: 0, sliderMax: 250),
                        ParamSpec(key: "height", label: "Height", type: .length, defaultValue: "10", sliderMin: 0.1, sliderMax: 500),
                    ] + atParams()),
        CommandSpec(id: "torus", title: "Torus", group: "Primitives",
                    summary: "Torus in the XY plane.",
                    params: [
                        ParamSpec(key: "ringRadius", label: "Ring radius", type: .length, defaultValue: "10", sliderMin: 0.1, sliderMax: 250),
                        ParamSpec(key: "tubeRadius", label: "Tube radius", type: .length, defaultValue: "3", sliderMin: 0.05, sliderMax: 125),
                    ] + atParams()),
        CommandSpec(id: "profile", title: "Profile", group: "Profiles",
                    summary: "Closed 2D polygon profile, extruded later.",
                    params: [
                        ParamSpec(key: "points", label: "Points (x,y ...)", type: .pointList, defaultValue: "0,0 40,0 40,20 0,20"),
                    ]),
        CommandSpec(id: "extrude", title: "Extrude", group: "Profiles",
                    summary: "Extrude a profile along +Z.",
                    params: [
                        ParamSpec(key: "profile", label: "Profile", type: .profileRef, defaultValue: ""),
                        ParamSpec(key: "distance", label: "Distance", type: .length, defaultValue: "10", sliderMin: 0.1, sliderMax: 500),
                    ]),
        CommandSpec(id: "union", title: "Union", group: "Booleans",
                    summary: "Fuse two solids into one.",
                    params: [
                        ParamSpec(key: "a", label: "First solid", type: .objectRef, defaultValue: ""),
                        ParamSpec(key: "b", label: "Second solid", type: .objectRef, defaultValue: ""),
                    ]),
        CommandSpec(id: "cut", title: "Cut", group: "Booleans",
                    summary: "Subtract the tool solid from the target.",
                    params: [
                        ParamSpec(key: "a", label: "Target", type: .objectRef, defaultValue: ""),
                        ParamSpec(key: "b", label: "Tool (subtracted)", type: .objectRef, defaultValue: ""),
                    ]),
        CommandSpec(id: "intersect", title: "Intersect", group: "Booleans",
                    summary: "Keep only the volume common to both solids.",
                    params: [
                        ParamSpec(key: "a", label: "First solid", type: .objectRef, defaultValue: ""),
                        ParamSpec(key: "b", label: "Second solid", type: .objectRef, defaultValue: ""),
                    ]),
        CommandSpec(id: "fillet", title: "Fillet", group: "Modify",
                    summary: "Round edges (all, or the listed edge numbers).",
                    params: [
                        ParamSpec(key: "source", label: "Source", type: .objectRef, defaultValue: ""),
                        ParamSpec(key: "radius", label: "Radius", type: .length, defaultValue: "1", sliderMin: 0.01, sliderMax: 100),
                        ParamSpec(key: "edges", label: "Edges (blank = all)", type: .edgeList, defaultValue: ""),
                    ]),
        CommandSpec(id: "chamfer", title: "Chamfer", group: "Modify",
                    summary: "Chamfer edges (all, or the listed edge numbers).",
                    params: [
                        ParamSpec(key: "source", label: "Source", type: .objectRef, defaultValue: ""),
                        ParamSpec(key: "distance", label: "Distance", type: .length, defaultValue: "1", sliderMin: 0.01, sliderMax: 100),
                        ParamSpec(key: "edges", label: "Edges (blank = all)", type: .edgeList, defaultValue: ""),
                    ]),
        CommandSpec(id: "translate", title: "Translate", group: "Transform",
                    summary: "Moved copy of the source solid.",
                    params: [
                        ParamSpec(key: "source", label: "Source", type: .objectRef, defaultValue: ""),
                        ParamSpec(key: "dx", label: "Move X", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
                        ParamSpec(key: "dy", label: "Move Y", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
                        ParamSpec(key: "dz", label: "Move Z", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
                    ]),
        CommandSpec(id: "rotate", title: "Rotate", group: "Transform",
                    summary: "Rotated copy of the source solid.",
                    params: [
                        ParamSpec(key: "source", label: "Source", type: .objectRef, defaultValue: ""),
                        ParamSpec(key: "axisX", label: "Axis X", type: .number, defaultValue: "0", sliderMin: -1, sliderMax: 1),
                        ParamSpec(key: "axisY", label: "Axis Y", type: .number, defaultValue: "0", sliderMin: -1, sliderMax: 1),
                        ParamSpec(key: "axisZ", label: "Axis Z", type: .number, defaultValue: "1", sliderMin: -1, sliderMax: 1),
                        ParamSpec(key: "angle", label: "Angle (deg)", type: .angle, defaultValue: "90", sliderMin: -360, sliderMax: 360),
                        ParamSpec(key: "aboutX", label: "About X", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
                        ParamSpec(key: "aboutY", label: "About Y", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
                        ParamSpec(key: "aboutZ", label: "About Z", type: .number, defaultValue: "0", sliderMin: -500, sliderMax: 500),
                    ]),
        CommandSpec(id: "copy", title: "Copy", group: "Transform",
                    summary: "Exact copy of the source solid.",
                    params: [
                        ParamSpec(key: "source", label: "Source", type: .objectRef, defaultValue: ""),
                    ]),
    ]

    /// Group names in display order.
    public static let groupOrder = ["Primitives", "Profiles", "Booleans", "Modify", "Transform"]

    public static func spec(for id: String) -> CommandSpec? {
        all.first { $0.id == id }
    }

    public static func grouped() -> [(group: String, specs: [CommandSpec])] {
        groupOrder.compactMap { g in
            let specs = all.filter { $0.group == g }
            return specs.isEmpty ? nil : (group: g, specs: specs)
        }
    }
}
