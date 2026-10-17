import AppKit

public struct ImportedClip: Equatable, Sendable {
    public let representations: [Representation]
    public let created: Date
}

public struct HistoryImportCounts: Equatable, Sendable, Codable {
    public var imported = 0
    /// Already in history, so left where they were.
    public var duplicates = 0
    /// Nothing storable: an image bigger than the cap even as PNG, or an empty clip.
    public var skipped = 0
    /// History reached its size limit before every clip was in.
    public var stoppedFull = false

    public init() {}
}

public enum ClipMenuHistoryError: Error, CustomStringConvertible {
    case notAnArchive(String)

    public var description: String {
        switch self {
        case .notAnArchive(let reason): "not a ClipMenu history file: \(reason)"
        }
    }
}

/// ClipMenu's `clips.data`: an `NSKeyedArchiver` archive of an array of `Clip` objects, newest
/// first, as the menu shows them. Each clip keeps its text, RTF, RTFD, PDF, URLs, file paths and
/// an `NSImage` apiece. They are read with a stand-in class, so none of ClipMenu's code is needed.
public enum ClipMenuHistory {
    public static func parse(_ data: Data, maxImageBytes: Int) throws -> [ImportedClip] {
        let (clips, _) = try decode(data, maxImageBytes: maxImageBytes)
        return clips
    }

    /// Adds the clips below the current history, newest first, so ClipMenu's order is kept and the
    /// current clips stay on top. `limit` takes only that many of the newest. The file is read
    /// completely before anything is written, so a bad file changes nothing.
    public static func importFile(at url: URL, into store: HistoryStore, limit: Int?) throws -> HistoryImportCounts {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let (parsed, total) = try decode(data, maxImageBytes: store.limits.maxImageBytes)
        let chosen = limit.map { Array(parsed.prefix($0)) } ?? parsed

        var counts = HistoryImportCounts()
        counts.skipped = total - parsed.count
        for clip in chosen {
            switch try store.insertOlder(clip.representations, title: ClipboardMonitor.title(for: clip.representations), created: clip.created) {
            case .inserted: counts.imported += 1
            case .duplicate: counts.duplicates += 1
            case .empty: counts.skipped += 1
            case .full:
                counts.stoppedFull = true
                return counts
            }
        }
        return counts
    }

    /// The clips that have something to store, and how many the archive held.
    private static func decode(_ data: Data, maxImageBytes: Int) throws -> (clips: [ImportedClip], total: Int) {
        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            throw ClipMenuHistoryError.notAnArchive("\(error.localizedDescription)")
        }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(LegacyClip.self, forClassName: "Clip")
        defer { unarchiver.finishDecoding() }
        guard let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [Any] else {
            throw ClipMenuHistoryError.notAnArchive("no list of clips")
        }
        let legacy = root.compactMap { $0 as? LegacyClip }
        guard !legacy.isEmpty || root.isEmpty else { throw ClipMenuHistoryError.notAnArchive("no clips in the list") }
        let clips = legacy.compactMap { clip -> ImportedClip? in
            let reps = clip.representations(maxImageBytes: maxImageBytes)
            return reps.isEmpty ? nil : ImportedClip(representations: reps, created: clip.created)
        }
        return (clips, legacy.count)
    }
}

/// Stands in for ClipMenu's `Clip` while unarchiving. The key names are ClipMenu's own.
@objc(ClipHavenLegacyClip)
private final class LegacyClip: NSObject, NSCoding {
    let created: Date
    private let string: String?
    private let rtf: Data?
    private let rtfd: Data?
    private let pdf: Data?
    private let filenames: [String]
    private let urls: [String]
    private let image: NSImage?

    required init?(coder: NSCoder) {
        created = coder.decodeObject(forKey: "createdDate") as? Date ?? Date()
        string = coder.decodeObject(forKey: "stringValue") as? String
        rtf = coder.decodeObject(forKey: "RTF") as? Data
        rtfd = coder.decodeObject(forKey: "RTFD") as? Data
        pdf = coder.decodeObject(forKey: "PDF") as? Data
        filenames = coder.decodeObject(forKey: "filenames") as? [String] ?? []
        urls = coder.decodeObject(forKey: "URL") as? [String] ?? []
        image = coder.decodeObject(forKey: "image") as? NSImage
    }

    func encode(with coder: NSCoder) {}

    func representations(maxImageBytes: Int) -> [Representation] {
        var reps: [Representation] = []
        if let string, !string.isEmpty { reps.append(Representation(type: ClipType.string.pasteboardType, data: Data(string.utf8))) }
        if let rtf, !rtf.isEmpty { reps.append(Representation(type: ClipType.rtf.pasteboardType, data: rtf)) }
        if let rtfd, !rtfd.isEmpty { reps.append(Representation(type: ClipType.rtfd.pasteboardType, data: rtfd)) }
        if let pdf, !pdf.isEmpty { reps.append(Representation(type: ClipType.pdf.pasteboardType, data: pdf)) }
        if let url = urls.first, !url.isEmpty { reps.append(Representation(type: ClipType.url.pasteboardType, data: Data(url.utf8))) }
        if !filenames.isEmpty {
            let lines = filenames.map { URL(fileURLWithPath: $0).absoluteString }
            reps.append(Representation(type: ClipType.filenames.pasteboardType, data: Data(lines.joined(separator: "\n").utf8)))
        }
        if let picture = picture(maxImageBytes: maxImageBytes) { reps.append(picture) }
        return reps
    }

    /// The image as TIFF, or as lossless PNG when the TIFF is over the cap and the PNG is not.
    private func picture(maxImageBytes: Int) -> Representation? {
        guard let image else { return nil }
        let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.first
        guard let tiff = bitmap?.tiffRepresentation ?? image.tiffRepresentation else { return nil }
        if tiff.count <= maxImageBytes { return Representation(type: ClipType.tiff.pasteboardType, data: tiff) }
        guard let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              png.count <= maxImageBytes else { return nil }
        return Representation(type: ClipType.png.pasteboardType, data: png)
    }
}
