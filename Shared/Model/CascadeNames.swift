import Foundation

// MARK: - Qualified names + name directories (v0.3.0)
//
// Every object/profile in a session lives in a DIRECTORY named after
// the command that created it (box/, cylinder/, cut/, ...). The
// session key is the qualified "dir:name"; the display name (after
// the colon) is what the UI shows. Uniqueness is per-directory only.
//
// These helpers are the Swift mirror of the session layer's rules
// (Core/native/src/cc_interpreter.cpp, claimName / resolveObjectKey):
//
//   * uniqueName(directory:requested:existing:) — the requested
//     display name when free in that directory, else the first free
//     numeric suffix, incrementing a trailing number
//     (part -> part2, part2 -> part3). The engine applies the same
//     rule when a create collides, so a name predicted here and a
//     name claimed there agree; the harness pins the parity against
//     an engine-generated fixture.
//   * autoName(directory:existing:) — "<directory><n>" with the
//     lowest free n >= 1, used when the user leaves the name field
//     empty ("Names will be automatically assigned if none is given").
//   * Resolution of a bare display name (engine rule): qualified
//     exact match, then the context directory, then a UNIQUE bare
//     match across directories; several matches are an error, never
//     a guess. The UI sidesteps ambiguity by storing qualified names
//     in step parameters (pickers hand out qualified names).
//
// Pure Foundation — compiled into the app AND into the CI Swift
// harness, which executes these functions against real backend data.

public enum CascadeNames {

    /// Canonical directory order for display (creation-command order).
    public static let directoryOrder: [String] = [
        "box", "cylinder", "sphere", "cone", "torus",
        "profile", "extrude", "revolve", "loft", "sweep",
        "union", "cut", "intersect",
        "fillet", "chamfer", "shell",
        "translate", "rotate", "copy", "mirror", "pattern",
    ]

    public static func isQualified(_ name: String) -> Bool {
        name.contains(":")
    }

    /// "box:part" -> "box"; a bare name has directory "".
    public static func directory(of qualified: String) -> String {
        guard let idx = qualified.firstIndex(of: ":") else { return "" }
        return String(qualified[..<idx])
    }

    /// "box:part" -> "part"; a bare name is its own display name.
    public static func display(of qualified: String) -> String {
        guard let idx = qualified.firstIndex(of: ":") else { return qualified }
        return String(qualified[qualified.index(after: idx)...])
    }

    public static func qualify(directory: String, display: String) -> String {
        directory + ":" + display
    }

    /// Display names currently taken inside one directory.
    public static func takenDisplays(directory: String, existing: [String]) -> Set<String> {
        Set(existing.filter { self.directory(of: $0) == directory }
            .map { display(of: $0) })
    }

    /// Mirror of the engine's claimName suffix rule.
    public static func uniqueName(directory: String, requested: String,
                                  existing: [String]) -> String {
        let taken = takenDisplays(directory: directory, existing: existing)
        if !taken.contains(requested) { return requested }
        var stem = requested
        var n = 1
        var cut = requested.endIndex
        while cut > requested.startIndex {
            let prev = requested.index(before: cut)
            if !requested[prev].isNumber { break }
            cut = prev
        }
        if cut < requested.endIndex {
            stem = String(requested[..<cut])
            n = Int(requested[cut...]) ?? 1
        }
        var k = n + 1
        while taken.contains(stem + String(k)) { k += 1 }
        return stem + String(k)
    }

    /// "<directory><lowest free n>" — box1, box2, ... in box/.
    public static func autoName(directory: String, existing: [String]) -> String {
        let taken = takenDisplays(directory: directory, existing: existing)
        var n = 1
        while taken.contains(directory + String(n)) { n += 1 }
        return directory + String(n)
    }

    /// Group qualified names by directory for the part tree:
    /// directories in canonical order (unknown ones after, sorted),
    /// display names sorted within each directory.
    public static func grouped(_ qualifiedNames: [String])
        -> [(directory: String, names: [String])] {
        var byDir: [String: [String]] = [:]
        for name in qualifiedNames {
            byDir[directory(of: name), default: []].append(name)
        }
        let ordered = byDir.keys.sorted { a, b in
            let ia = directoryOrder.firstIndex(of: a) ?? Int.max
            let ib = directoryOrder.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            return a < b
        }
        return ordered.map { dir in
            (directory: dir, names: (byDir[dir] ?? []).sorted())
        }
    }
}
