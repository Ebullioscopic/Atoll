// swift-tools-version: 5.9
import PackageDescription

// Standalone test package for Atoll decision-logic that Codacy's PR #3 review
// flagged as lacking automated coverage. These are *pure-logic parity* tests:
// each source type mirrors — with a `// MIRRORS:` reference back to the
// canonical implementation — the small, hardware-free decision kernels embedded
// inside the app's hardware-coupled singletons (SystemBrightnessController and
// ContentView's sticky-terminal outside-click monitor). The kernels mirror what
// the app actually does; where a Codacy proposal described behaviour the app
// does not implement, it is documented as not-applicable instead of faked. Types
// are `internal` (this package exists only for its own test target).
//
// Why a separate package instead of an in-app XCTest target:
//   * The app is a single `DynamicIsland` application target with no existing
//     test target; bundling XCTest into a macOS .app needs a test host + signing.
//   * The relevant logic is `private` inside singletons that touch CoreBrightness,
//     IODisplay, DistributedNotificationCenter and NSEvent global monitors —
//     none of which run deterministically in CI.
//   * This package builds & runs with a plain `swift test`, no Xcode app build,
//     so it stays green under the heavy concurrent SPM contention on this repo.
//
// Follow-up (tracked in the PR body): extract the mirrored kernels into a shared
// `AtollLogic` source file the app itself imports, so app + tests share one
// definition instead of a verified copy.
let package = Package(
    name: "AtollLogic",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AtollLogic"),
        .testTarget(name: "AtollLogicTests", dependencies: ["AtollLogic"])
    ]
)
