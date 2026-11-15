import AppKit

/// Pre-rendered SVG exports avoid runtime SVG filter/mask differences.
/// Separate logical sizes retain appropriate 1x and 2x representations.
@MainActor
enum BrandAssets {
    // SwiftPM's default lookup uses the app root, which strict codesigning
    // rejects for nested resource bundles. Packaged apps use Contents/Resources;
    // command-line builds and tests use the generated SwiftPM accessor.
    static let resourceBundle: Bundle = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Scribbit_Scribbit.bundle"),
                  let bundle = Bundle(url: url) else {
                preconditionFailure("Missing packaged branding resource bundle")
            }
            return bundle
        }
        return Bundle.module
    }()
    static let notch = template(size: 14)
    static let menuBar = template(size: 18)

    private static func template(size: Int) -> NSImage {
        let logicalSize = NSSize(width: size, height: size)
        let image = NSImage(size: logicalSize)
        for suffix in ["", "@2x"] {
            guard let url = resourceBundle.url(forResource: "FrogPencil-\(size)\(suffix)", withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else {
                preconditionFailure("Missing bundled frog-and-pencil image")
            }
            representation.size = logicalSize
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        image.accessibilityDescription = "Scribbit frog holding a pencil"
        return image
    }
}
