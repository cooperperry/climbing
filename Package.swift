// swift-tools-version:5.9
import PackageDescription

// This package is a Linux/CI validation harness for the platform-independent
// domain layer of the iOS app. It compiles the exact same source files that ship
// in the app target (`Climbing/Domain`) so their logic can be unit tested without
// macOS, Xcode, SwiftUI, or SwiftData. The SwiftData models and SwiftUI views are
// intentionally excluded — they require the Apple SDKs and are built in Xcode.
let package = Package(
    name: "ClimbingDomain",
    products: [
        .library(name: "ClimbingDomain", targets: ["ClimbingDomain"]),
    ],
    targets: [
        .target(
            name: "ClimbingDomain",
            path: "Climbing/Domain"
        ),
        .testTarget(
            name: "ClimbingDomainTests",
            dependencies: ["ClimbingDomain"],
            path: "Tests/ClimbingDomainTests"
        ),
    ]
)
