//
//  ViewCommands.swift
//  Cascade Console - Viewer
//
//  Text -> ViewerCommand parsing for every `view ...` console command.
//  Grammar (case-insensitive keywords; object ids are case-sensitive):
//
//    view fit
//    view top|bottom|front|back|left|right|iso
//    view shaded | wireframe | edges        (edges = shaded+edges)
//    view xray | transparent | solid        (solid = back to shaded)
//    view section off
//    view section x|y|z <distance>
//    view section <nx> <ny> <nz> <constant>
//    view explode <factor 0...2>
//    view screenshot [path] [width height]  (default: ~/Pictures shot, 1600x1200)
//    view measure on|off|clear
//    view grid on|off
//    view axes on|off
//    view background <topHex> <bottomHex>   (RRGGBB, e.g. 1a1c20)
//    view projection ortho|perspective
//    view hide <id> | view show <id>
//    view opacity <id> <0...1>
//    view color <id> <RRGGBB>
//    view reset
//
//  Parse failures return a plain-language message - the console shows
//  it verbatim; nothing is applied partially.
//

import Foundation
import simd

/// Parse failure for a `view ...` line. `Result`'s failure type must
/// conform to `Error`, which `String` does not - the parser originally
/// used a plain String as its failure type, which does not type-check
/// and cascaded into every `.success(...)` case in the parser. The
/// console shows `message` verbatim, exactly as before.
public struct ViewCommandParseError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum ViewCommandParser {
    public static func parse(_ rawLine: String) -> Result<ViewerCommand, ViewCommandParseError> {
        var tokens = rawLine.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard tokens.count >= 2, tokens[0].lowercased() == "view" else {
            return .failure(ViewCommandParseError("not a view command"))
        }
        tokens.removeFirst() // "view"
        let head = tokens[0].lowercased()
        let args = Array(tokens.dropFirst())

        func onOff(_ s: String?) -> Bool? {
            switch s?.lowercased() {
            case "on", "true", "yes", "1": return true
            case "off", "false", "no", "0": return false
            default: return nil
            }
        }
        func hexColor(_ s: String) -> SIMD4<Float>? {
            var hex = s
            if hex.hasPrefix("#") { hex.removeFirst() }
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
            return SIMD4<Float>(Float((v >> 16) & 0xff) / 255,
                                Float((v >> 8) & 0xff) / 255,
                                Float(v & 0xff) / 255, 1)
        }

        switch head {
        case "labels":
            // view labels faces on|off
            guard args.count == 2, args[0].lowercased() == "faces",
                  let on = onOff(args[1]) else {
                return .failure(ViewCommandParseError("usage: view labels faces on|off"))
            }
            return .success(.setFaceLabelsEnabled(on))
        case "fit":
            return .success(.fit)
        case "top", "bottom", "front", "back", "left", "right", "iso":
            return .success(.standardView(StandardView(rawValue: head)!))
        case "shaded":
            return .success(.displayMode(.shaded))
        case "wireframe":
            return .success(.displayMode(.wireframe))
        case "edges":
            return .success(.displayMode(.shadedWithEdges))
        case "xray":
            return .success(.displayMode(.xray))
        case "transparent":
            return .success(.displayMode(.transparent))
        case "solid":
            return .success(.displayMode(.shaded))
        case "section":
            if args.count == 1, args[0].lowercased() == "off" {
                return .success(.setSection(nil))
            }
            if args.count == 2, let plane = SectionPlane.axis(args[0],
                                                              distance: Float(args[1]) ?? .nan),
               Float(args[1]) != nil {
                return .success(.setSection(plane))
            }
            if args.count == 4,
               let nx = Float(args[0]), let ny = Float(args[1]),
               let nz = Float(args[2]), let c = Float(args[3]) {
                return .success(.setSection(SectionPlane(
                    normal: SIMD3<Float>(nx, ny, nz), constant: c)))
            }
            return .failure(ViewCommandParseError("usage: view section off | view section x|y|z <distance> | view section <nx> <ny> <nz> <constant>"))
        case "explode":
            guard args.count == 1, let f = Float(args[0]), (0...2).contains(f) else {
                return .failure(ViewCommandParseError("usage: view explode <factor 0...2>"))
            }
            return .success(.setExplode(factor: f))
        case "screenshot", "render":
            let path = args.first ?? defaultScreenshotPath()
            var width = 1600, height = 1200
            if args.count >= 3, let w = Int(args[1]), let h = Int(args[2]), w > 0, h > 0 {
                width = w; height = h
            }
            return .success(.screenshot(path: path, width: width, height: height))
        case "measure":
            guard let first = args.first?.lowercased() else {
                return .failure(ViewCommandParseError("usage: view measure on|off|clear"))
            }
            if first == "clear" { return .success(.clearMeasure) }
            guard let on = onOff(first) else {
                return .failure(ViewCommandParseError("usage: view measure on|off|clear"))
            }
            return .success(.setMeasureEnabled(on))
        case "grid":
            guard let on = onOff(args.first) else {
                return .failure(ViewCommandParseError("usage: view grid on|off"))
            }
            return .success(.setGridVisible(on))
        case "axes":
            guard let on = onOff(args.first) else {
                return .failure(ViewCommandParseError("usage: view axes on|off"))
            }
            return .success(.setAxesVisible(on))
        case "background", "bg":
            guard args.count == 2, let top = hexColor(args[0]),
                  let bottom = hexColor(args[1]) else {
                return .failure(ViewCommandParseError("usage: view background <top RRGGBB> <bottom RRGGBB>"))
            }
            return .success(.setBackground(top: top, bottom: bottom))
        case "projection":
            guard let mode = args.first?.lowercased(),
                  mode == "ortho" || mode == "perspective" else {
                return .failure(ViewCommandParseError("usage: view projection ortho|perspective"))
            }
            return .success(.setProjection(mode == "ortho" ? .orthographic : .perspective))
        case "hide":
            guard let id = args.first else { return .failure(ViewCommandParseError("usage: view hide <object>")) }
            return .success(.setObjectVisible(id: id, false))
        case "show":
            guard let id = args.first else { return .failure(ViewCommandParseError("usage: view show <object>")) }
            return .success(.setObjectVisible(id: id, true))
        case "opacity":
            guard args.count == 2, let v = Float(args[1]), (0...1).contains(v) else {
                return .failure(ViewCommandParseError("usage: view opacity <object> <0...1>"))
            }
            return .success(.setObjectOpacity(id: args[0], v))
        case "color", "colour":
            guard args.count == 2, let c = hexColor(args[1]) else {
                return .failure(ViewCommandParseError("usage: view color <object> <RRGGBB>"))
            }
            return .success(.setObjectColor(id: args[0], c))
        case "reset":
            return .success(.resetCamera)
        default:
            return .failure(ViewCommandParseError("unknown view command '\(head)' - try view fit, view iso, view wireframe, view section, view explode, view screenshot, view measure, view grid, view projection"))
        }
    }

    private static func defaultScreenshotPath() -> String {
        let pictures = FileManager.default.urls(for: .picturesDirectory,
                                                in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return pictures.appendingPathComponent("cascade-\(stamp).png").path
    }
}
