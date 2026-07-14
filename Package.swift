// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CatchIt",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CatchIt", targets: ["CatchIt"])
    ],
    targets: [
        .executableTarget(
            name: "CatchIt",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
