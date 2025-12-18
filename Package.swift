// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "NekoTerm",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../SwiftTerm")
    ],
    targets: [
        .executableTarget(
            name: "NekoTerm",
            dependencies: ["SwiftTerm"]
        )
    ]
)
