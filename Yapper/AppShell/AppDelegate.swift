import AppKit

/// Owns the live composition and starts it once the app has launched.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// nil when the binary is hosting unit tests: tests must not register the real shortcut.
    let composition: AppComposition? =
        LaunchEnvironment.isHostingTests(ProcessInfo.processInfo.environment) ? nil : .live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let composition else { return }
        Task { await composition.start() }
    }
}
