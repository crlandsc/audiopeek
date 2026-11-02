import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
enum RenderPlaywave {
    static func main() throws {
        let catalog = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

        let slots = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for (name, side) in slots {
            write(PlaywaveMark.iconImage(side: side), to: catalog.appendingPathComponent(name))
        }
        if CommandLine.arguments.count > 2 {
            let readme = URL(fileURLWithPath: CommandLine.arguments[2])
            write(PlaywaveMark.readmeImage(width: 1024), to: readme)
        }
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fputs("Could not write \(url.path)\n", stderr)
            exit(1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            fputs("Could not write \(url.path)\n", stderr)
            exit(1)
        }
    }
}
