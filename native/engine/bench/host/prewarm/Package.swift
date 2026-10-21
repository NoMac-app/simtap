// swift-tools-version:5.9
// Built once per pool user before a session is handed out, so the customer's first xcodebuild finds Xcode warm.
import PackageDescription
let package = Package(name: "Prewarm", platforms: [.iOS(.v17)], products: [.library(name: "Prewarm", targets: ["Prewarm"])], targets: [.target(name: "Prewarm")])
