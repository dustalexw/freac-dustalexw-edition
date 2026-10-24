// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Frickoss",
    platforms: [.macOS(.v13)],
    // The app ships as "frickoss.app".
    products: [.executable(name: "Frickoss", targets: ["Frickoss"])],
    targets: [
        .executableTarget(name: "Frickoss", path: "Sources/Frickoss")
    ]
)
