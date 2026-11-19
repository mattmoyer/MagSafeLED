// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-2.0-or-later
import PackageDescription

let package = Package(
    name: "MagSafeLED",
    platforms: [.macOS(.v13)],
    targets: [
        // C struct definition, so the 80-byte SMC parameter layout matches the kernel exactly.
        .target(name: "CSMC"),
        .target(name: "SMCKit", dependencies: ["CSMC"], linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "Shared"),
        .executableTarget(name: "magsafeledd", dependencies: ["SMCKit", "Shared", "CSMC"],
                          linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "MagSafeLED", dependencies: ["SMCKit", "Shared", "CSMC"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]),
    ]
)
