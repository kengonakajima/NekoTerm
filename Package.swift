// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Nekotty",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../SwiftTerm")
    ],
    targets: [
        .executableTarget(
            name: "Nekotty",
            dependencies: ["SwiftTerm"]
        )
    ]
)
