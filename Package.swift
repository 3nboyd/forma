// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Forma",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Forma", targets: ["FormaApp"]), .library(name: "FormaCore", targets: ["FormaCore"])],
    targets: [
        .target(name: "FormaCore"),
        .executableTarget(name: "FormaApp", dependencies: ["FormaCore"]),
        .testTarget(name: "FormaCoreTests", dependencies: ["FormaCore"])
    ],
    swiftLanguageModes: [.v5]
)
