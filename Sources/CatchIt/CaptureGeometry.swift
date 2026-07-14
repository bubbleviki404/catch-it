import CoreGraphics

enum CaptureGeometry {
    static func outputPixelSize(
        screenSize: CGSize,
        localRect: CGRect,
        displayPixelSize: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGSize {
        let displayScaleX = screenSize.width > 0 ? displayPixelSize.width / screenSize.width : 1
        let displayScaleY = screenSize.height > 0 ? displayPixelSize.height / screenSize.height : 1
        // Some ScreenCaptureKit versions report SCDisplay dimensions in
        // logical points. NSScreen.backingScaleFactor is authoritative for
        // Retina output, while the display ratio covers APIs returning pixels.
        let scaleX = max(1, backingScaleFactor, displayScaleX)
        let scaleY = max(1, backingScaleFactor, displayScaleY)
        return CGSize(
            width: max(2, (localRect.width * scaleX).rounded()),
            height: max(2, (localRect.height * scaleY).rounded())
        )
    }
}
