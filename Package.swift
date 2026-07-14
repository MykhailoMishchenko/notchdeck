// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchDeck",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NotchDeck",
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
        )
    ]
)
