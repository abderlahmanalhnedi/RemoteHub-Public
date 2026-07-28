import SwiftUI

@main
@MainActor
struct RemoteHubApp: App {
    @State private var container: AppContainer?
    @State private var startupError: String?

    init() {
        do {
            _container = State(initialValue: try AppContainer())
        } catch {
            _container = State(initialValue: nil)
            _startupError = State(initialValue: Redactor.sanitize(error.localizedDescription))
        }
    }

    var body: some Scene {
        WindowGroup(AppConstants.productName) {
            if let container {
                RootView()
                    .environment(container)
                    .modelContainer(container.modelContainer)
                    .preferredColorScheme(preferredScheme(container.settings.appearance))
                    .frame(minWidth: 960, minHeight: 640)
            } else {
                ContentUnavailableView(
                    "RemoteHub could not start",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(startupError ?? "The local data store is unavailable.")
                )
                .frame(minWidth: 720, minHeight: 480)
            }
        }
        .defaultSize(width: 1240, height: 780)
        .commands { RemoteHubCommands() }

        Settings {
            if let container {
                SettingsView()
                    .environment(container)
                    .modelContainer(container.modelContainer)
                    .frame(width: 720, height: 580)
            } else {
                Text("Settings are unavailable.")
                    .padding()
            }
        }
    }

    private func preferredScheme(_ preference: AppearancePreference) -> ColorScheme? {
        switch preference {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
