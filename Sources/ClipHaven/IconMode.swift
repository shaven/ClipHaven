import Foundation

/// `ClipHaven --write-icon <out.png> <pixels> [app]`: writes the coloured icon as a PNG. The build
/// script uses it to make the app's `.icns`, so the icon is drawn from one place.
enum IconMode {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.count >= 4, args[1] == "--write-icon", let pixels = Int(args[3]), pixels > 0 else { return }
        guard let data = ColourIcon.png(pixels: pixels, forApp: args.count > 4 && args[4] == "app") else { exit(1) }
        do {
            try data.write(to: URL(fileURLWithPath: args[2]))
            exit(0)
        } catch {
            exit(1)
        }
    }
}
