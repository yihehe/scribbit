import AppKit
import ImageIO
import Testing
@testable import Scribbit

struct BrandAssetsTests {
    @Test func appIconExportDecodesAtRequiredPixelSizes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/AppIcon.icns")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        var sizes = Set<Int>()
        for index in 0..<CGImageSourceGetCount(source) {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            #expect(image.width == image.height)
            sizes.insert(image.width)
        }
        #expect(Set([16, 32, 64, 128, 256, 512, 1024]).isSubset(of: sizes))
    }

    @Test @MainActor func templatesHaveNativeSizesAndRetinaRepresentations() throws {
        for (image, size) in [(BrandAssets.notch, 14), (BrandAssets.menuBar, 18)] {
            #expect(image.isTemplate)
            #expect(image.size == NSSize(width: size, height: size))
            let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
            #expect(reps.count == 2)
            #expect(reps.map(\.pixelsWide).sorted() == [size, size * 2])
            #expect(reps.map(\.pixelsHigh).sorted() == [size, size * 2])
            for rep in reps {
                #expect(rep.hasAlpha)
                #expect(rep.size == image.size)
                let corner = try #require(rep.colorAt(x: 0, y: 0))
                #expect(corner.alphaComponent == 0)
                var filled = 0
                var empty = 0
                for y in 0..<rep.pixelsHigh {
                    for x in 0..<rep.pixelsWide {
                        let alpha = try #require(rep.colorAt(x: x, y: y)).alphaComponent
                        if alpha > 0.5 { filled += 1 }
                        if alpha < 0.1 { empty += 1 }
                    }
                }
                #expect(filled > 20)
                #expect(empty > 20)
            }
        }
        #expect(BrandAssets.notch !== BrandAssets.menuBar)
    }
}
