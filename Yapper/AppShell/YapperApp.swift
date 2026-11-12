import SwiftUI

@main
struct YapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            if let composition = appDelegate.composition {
                MenuBarContentView(app: composition)
            } else {
                Text(verbatim: "Yapper test host")
                    .padding()
            }
        } label: {
            Image(systemName: StatusPresentation.symbol(for: appDelegate.composition?.coordinator.state ?? .idle))
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView()
        }
    }
}
