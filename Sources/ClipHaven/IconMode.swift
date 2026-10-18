import Foundation

/// `ClipHaven --write-icon <out.png> <pixels>`: writes the small menu-bar icon as a PNG, for previewing it.
enum IconMode {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.count >= 4, args[1] == "--write-icon", let pixels = Int(args[3]), pixels > 0 else { return }
        guard let data = ColourIcon.png(pixels: pixels) else { exit(1) }
        do {
            try data.write(to: URL(fileURLWithPath: args[2]))
            exit(0)
        } catch {
            exit(1)
        }
    }
}
