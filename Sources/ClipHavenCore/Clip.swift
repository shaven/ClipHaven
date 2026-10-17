/// The pasteboard types ClipHaven keeps: ClipMenu's eight, plus PNG, which modern apps put
/// alongside (or instead of) TIFF for images.
public enum ClipType: String, CaseIterable, Sendable {
    case string, rtf, rtfd, pdf, tiff, png, pict, url, filenames

    /// The uniform type identifier on the pasteboard.
    public var pasteboardType: String {
        switch self {
        case .string: "public.utf8-plain-text"
        case .rtf: "public.rtf"
        case .rtfd: "com.apple.flat-rtfd"
        case .pdf: "com.adobe.pdf"
        case .tiff: "public.tiff"
        case .png: "public.png"
        case .pict: "com.apple.pict"
        case .url: "public.url"
        case .filenames: "public.file-url"
        }
    }

    /// The name ClipMenu's preferences use for this type.
    public var clipMenuName: String {
        switch self {
        case .string: "String"
        case .rtf: "RTF"
        case .rtfd: "RTFD"
        case .pdf: "PDF"
        case .tiff: "TIFF"
        case .png: "PNG"
        case .pict: "PICT"
        case .url: "URL"
        case .filenames: "Filenames"
        }
    }

    /// Menu title for a clip that has no text to show.
    var fallbackTitle: String {
        switch self {
        case .tiff, .png, .pict: "Image (\(clipMenuName))"
        default: clipMenuName
        }
    }

    init?(pasteboardType: String) {
        guard let match = Self.allCases.first(where: { $0.pasteboardType == pasteboardType }) else { return nil }
        self = match
    }
}
