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

public enum MenuIconTint: Equatable, Hashable, Sendable {
    case blue, orange, red, teal, green, gray, indigo, yellow, purple
}

extension MenuIconKind {
    /// The SF Symbol drawn for this kind; nil for a folder, which keeps Finder's own icon.
    public var symbol: String? {
        switch self {
        case .text: "doc.text.fill"
        case .richText: "doc.richtext.fill"
        case .pdf: "doc.fill"
        case .url: "link.circle.fill"
        case .files: "doc.on.doc.fill"
        case .image: "photo.fill"
        case .other: "questionmark.square.fill"
        case .folder: nil
        case .snippet: "note.text"
        case .lockedSnippet: "lock.fill"
        case .action: "bolt.fill"
        case .script: "curlybraces"
        }
    }

    public var tint: MenuIconTint {
        switch self {
        case .text, .action: .blue
        case .richText, .lockedSnippet: .orange
        case .pdf: .red
        case .url: .teal
        case .image: .green
        case .files: .indigo
        case .snippet, .folder: .yellow
        case .script: .purple
        case .other: .gray
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

/// A status-bar icon. `colour` and `template` are ClipHaven's own, drawn in code (the template one
/// is black and tinted by macOS); the rest are ClipMenu's
/// icons (MIT), kept in `Resources/StatusIcons`.
public struct StatusIconChoice: Equatable, Sendable {
    public let id: String
    public let title: String
    /// File name in `StatusIcons`, nil for the drawn template icon.
    public let file: String?

    public static let colour = StatusIconChoice(id: "colour", title: "ClipHaven (colour)", file: nil)
    public static let template = StatusIconChoice(id: "template", title: "ClipHaven (black and white, follows light and dark)", file: nil)
    public static let `default` = colour
    public static let all: [StatusIconChoice] = [
        colour,
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
    public var isColour: Bool { id.contains("colo") }

    /// The choice with this id, or the default when there is none.
    public static func resolve(_ id: String) -> StatusIconChoice {
        all.first { $0.id == id } ?? .default
    }
}
