import SwiftUI

extension Notification.Name {
    static let remoteHubNewConnection = Notification.Name("RemoteHub.newConnection")
    static let remoteHubFocusSearch = Notification.Name("RemoteHub.focusSearch")
    static let remoteHubCloseTab = Notification.Name("RemoteHub.closeTab")
    static let remoteHubReconnect = Notification.Name("RemoteHub.reconnect")
    static let remoteHubToggleFiles = Notification.Name("RemoteHub.toggleFiles")
}

struct RemoteHubCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Connection") {
                NotificationCenter.default.post(name: .remoteHubNewConnection, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
        CommandMenu("Connection") {
            Button("Focus Search") {
                NotificationCenter.default.post(name: .remoteHubFocusSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
            Button("Reconnect or Refresh") {
                NotificationCenter.default.post(name: .remoteHubReconnect, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
            Button("Toggle Remote Files") {
                NotificationCenter.default.post(name: .remoteHubToggleFiles, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Close Active Tab") {
                NotificationCenter.default.post(name: .remoteHubCloseTab, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command])
        }
    }
}
