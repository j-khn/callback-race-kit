// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CallbackRaceKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "CallbackRaceKit", targets: ["CallbackRaceKit"])
    ],
    targets: [
        .target(name: "CallbackRaceKit"),
        .testTarget(name: "CallbackRaceKitTests", dependencies: ["CallbackRaceKit"])
    ]
)
