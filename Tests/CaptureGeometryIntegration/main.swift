import CoreGraphics
import Foundation

let retina = CaptureGeometry.outputPixelSize(
    screenSize: CGSize(width: 1512, height: 982),
    localRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
    displayPixelSize: CGSize(width: 1512, height: 982),
    backingScaleFactor: 2
)
guard retina == CGSize(width: 3024, height: 1964) else {
    fputs("FAIL: Retina output should be 3024x1964, got \(retina)\n", stderr)
    exit(1)
}

let nonRetina = CaptureGeometry.outputPixelSize(
    screenSize: CGSize(width: 1920, height: 1080),
    localRect: CGRect(x: 100, y: 100, width: 800, height: 600),
    displayPixelSize: CGSize(width: 1920, height: 1080),
    backingScaleFactor: 1
)
guard nonRetina == CGSize(width: 800, height: 600) else {
    fputs("FAIL: 1x output should preserve selection pixels, got \(nonRetina)\n", stderr)
    exit(1)
}

print("PASS: Retina capture scales logical points to physical pixels")
