/// How the process was launched. The app binary also hosts the unit tests, which must never
/// register the real shortcut or query system status, so the live app is not started there.
enum LaunchEnvironment {
    /// Xcode sets `XCTestConfigurationFilePath` when it launches the app as a test host
    /// (both XCTest and Swift Testing runs).
    static func isHostingTests(_ environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
