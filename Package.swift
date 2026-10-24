// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreacEdition",
    platforms: [.macOS(.v13)],
    // The app ships as "freac (dustalexw edition).app"; the executable keeps a plain name.
    products: [.executable(name: "FreacEdition", targets: ["FreacEdition"])],
    targets: [
        .executableTarget(name: "FreacEdition", path: "Sources/FreacEdition")
    ]
)
