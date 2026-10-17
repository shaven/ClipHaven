import CoreGraphics
import Foundation

/// Which icon a menu entry gets. The app draws each kind (Finder icons for the clip types, as
/// ClipMenu does); this decides the kind, so it can be tested without a screen.
public enum MenuIconKind: Equatable, Sendable {
    case text, richText, pdf, url, files, image, other
    case folder, snippet, lockedSnippet, action, script

    public static func kind(forClipType type: String) -> MenuIconKind {
        switch type {
        case ClipType.string.pasteboardType: .text
        case ClipType.rtf.pasteboardType, ClipType.rtfd.pasteboardType: .richText
        case ClipType.pdf.pasteboardType: .pdf
        case ClipType.url.pasteboardType: .url
        case ClipType.filenames.pasteboardType: .files
        case ClipType.tiff.pasteboardType, ClipType.png.pasteboardType, ClipType.pict.pasteboardType: .image
        default: .other
        }
    }
}

public enum Thumbnail {
    /// The size an image is drawn at inside `box`: the same shape, never enlarged.
    public static func size(for pixels: CGSize, within box: CGSize) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return .zero }
        let scale = min(1, box.width / pixels.width, box.height / pixels.height)
        return CGSize(width: pixels.width * scale, height: pixels.height * scale)
    }
}

/// How the menu looks, from `Preferences`.
public struct MenuAppearance: Equatable, Sendable {
    public var showIcons = true
    public var iconSize = 16
    public var showThumbnails = true
    public var thumbnailSize = CGSize(width: 100, height: 32)

    public init() {}
}

/// A status-bar icon. `template` is ClipHaven's own, tinted by macOS; the rest are ClipMenu's
/// icons (MIT), kept in `Resources/StatusIcons`.
public struct StatusIconChoice: Equatable, Sendable {
    public let id: String
    public let title: String
    /// File name in `StatusIcons`, nil for the drawn template icon.
    public let file: String?

    public static let template = StatusIconChoice(id: "template", title: "ClipHaven (follows light and dark)", file: nil)
    public static let all: [StatusIconChoice] = [
        template,
        StatusIconChoice(id: "clipmenu", title: "ClipMenu", file: "StatusMenuIcon.png"),
        StatusIconChoice(id: "first", title: "ClipMenu, first", file: "StatusMenuIconFirst.png"),
        StatusIconChoice(id: "suphi", title: "Suphi Aksoy", file: "StatusMenuIconBySuphiAksoy.png"),
        StatusIconChoice(id: "diagonal-color", title: "Diagonal scissors, colour", file: "StatusMenuIconByDaveUlrich-diagonal-color.png"),
        StatusIconChoice(id: "scissors1-color", title: "Scissors 1, colour", file: "StatusMenuIconByDaveUlrich-scissors1-color-left.png"),
        StatusIconChoice(id: "scissors2-color", title: "Scissors 2, colour", file: "StatusMenuIconByDaveUlrich-scissors2-color-left.png"),
        StatusIconChoice(id: "diagonal-bw", title: "Diagonal scissors, black and white", file: "StatusMenuIconByDaveUlrich-diagonal-bw.png"),
    ]

    /// A coloured icon is drawn as it is; the others are black shapes that macOS tints.
    public var isColour: Bool { id.contains("color") }

    /// The choice with this id, or the template when there is none.
    public static func resolve(_ id: String) -> StatusIconChoice {
        all.first { $0.id == id } ?? template
    }
}
