// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchDeck",
    platforms: [.macOS(.v13)],
    targets: [
        // Shared between the app and the privileged helper: SMC access + the XPC contract.
        .target(
            name: "NotchDeckShared",
            path: "Sources/NotchDeckShared"
        ),
        .executableTarget(
            name: "NotchDeck",
            dependencies: ["NotchDeckShared"],
            path: "Sources/NotchDeck",
            exclude: ["Resources/Info-embedded.plist"],
            linkerSettings: [
                // Embed Info.plist into the bare binary so TCC prompts (calendar, apple events) work in dev runs without the .app bundle.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/NotchDeck/Resources/Info-embedded.plist",
                ])
            ]
        ),
        // Root launchd daemon (registered via SMAppService.daemon): owns SMC WRITES, exposes the narrow FanControl XPC service.
        .executableTarget(
            name: "NotchDeckFanHelper",
            dependencies: ["NotchDeckShared"],
            path: "Sources/NotchDeckFanHelper"
        ),
    ]
)
