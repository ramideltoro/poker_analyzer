// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacPokerCoach",
    platforms: [.macOS("15.2")],
    products: [.executable(name:"MacPokerCoach",targets:["MacPokerCoach"])],
    targets: [
        .target(name:"CPokerEvaluator"),
        .target(name:"PokerCore",dependencies:["CPokerEvaluator"],resources:[.copy("Resources")]),
        .target(name:"TableRecognition",dependencies:["PokerCore"]),
        .executableTarget(name:"MacPokerCoach",dependencies:["PokerCore","TableRecognition"]),
        .testTarget(name:"PokerCoreTests",dependencies:["PokerCore"]),
        .testTarget(name:"TableRecognitionTests",dependencies:["TableRecognition"],resources:[.copy("Fixtures")]),
        .testTarget(name:"MacPokerCoachTests",dependencies:["MacPokerCoach"])
    ]
)
