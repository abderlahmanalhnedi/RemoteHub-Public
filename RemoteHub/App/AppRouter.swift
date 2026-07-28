import Foundation
import Observation

enum SidebarSelection: Hashable {
    case dashboard
    case favorites
    case allConnections
    case group(UUID)
    case connectionProtocol(ConnectionKind)
    case credentials
    case workspace
    case settings
}

@MainActor
@Observable
final class AppRouter {
    var sidebarSelection: SidebarSelection? = .dashboard
    var selectedConnectionID: UUID?
    var searchText = ""
    var sortOption: SortOption = .name
    var connectionEditorID: UUID?
    var showsNewConnection = false
    var credentialEditorID: UUID?
    var showsNewCredential = false

    func edit(_ connection: ConnectionProfile) {
        connectionEditorID = connection.id
        showsNewConnection = false
    }

    func newConnection() {
        connectionEditorID = nil
        showsNewConnection = true
    }
}
