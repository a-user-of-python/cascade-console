import Foundation

// MARK: - Command history (the `history` command's data — INTEGRATION)
//
// Resolution (a) in INTEGRATION-NOTES.md: bare `history` is THIS — the
// session command log (every executed line, numbered, re-runnable).
// The OCCT BRepTools_History query is a different command:
// `shape-history <name>`.
//
// Both app scaffolds implemented Up/Down navigation identically; this
// is the single shared implementation both AppStates should use.

public struct CommandHistory: Equatable {
    public private(set) var lines: [String] = []
    private var index: Int?

    public init() {}

    public mutating func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lines.append(trimmed)
        index = nil
    }

    /// 1-based lookup for `history run <n>`; nil when out of range.
    public func line(atNumber n: Int) -> String? {
        guard n >= 1, n <= lines.count else { return nil }
        return lines[n - 1]
    }

    public mutating func previous(current: String) -> String {
        guard !lines.isEmpty else { return current }
        if let i = index { index = max(0, i - 1) } else { index = lines.count - 1 }
        if let i = index, lines.indices.contains(i) { return lines[i] }
        return current
    }

    public mutating func next(current: String) -> String {
        guard let i = index else { return current }
        let n = i + 1
        if n >= lines.count { index = nil; return "" }
        index = n
        return lines[n]
    }

    /// Numbered rendering printed by the `history` command.
    public var numberedText: String {
        lines.enumerated().map { "\($0.offset + 1)  \($0.element)" }.joined(separator: "\n")
    }
}
