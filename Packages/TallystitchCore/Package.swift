// swift-tools-version:5.7
import PackageDescription

// Why: the core domain logic (models, stock math, formatting) lives in a pure
// Foundation package with ZERO UIKit/SwiftUI dependency. Two payoffs:
//   1. It compiles + tests with the Command Line Tools alone (`swift test`),
//      so the stock-deduction math can be verified natively even on a machine
//      that can't build the full iOS app.
//   2. It keeps business rules out of the views — the same separation the web
//      app gets from src/lib/stock.ts.
let package = Package(
    name: "TallystitchCore",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [
        .library(name: "TallystitchCore", targets: ["TallystitchCore"]),
    ],
    targets: [
        .target(name: "TallystitchCore"),
        .testTarget(
            name: "TallystitchCoreTests",
            dependencies: ["TallystitchCore"]
        ),
    ]
)
