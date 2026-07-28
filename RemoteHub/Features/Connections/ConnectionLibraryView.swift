import SwiftUI

struct ConnectionLibraryView: View {
    @Environment(AppContainer.self) private var app
    let filter: SidebarSelection?
    @State private var deleteTarget: ConnectionProfile?
    @State private var operationError: String?

    private var displayedConnections: [ConnectionProfile] {
        var values = ConnectionSearch.filter(
            app.library.connections,
            query: app.router.searchText,
            groups: app.library.groups
        )
        switch filter {
        case .favorites:
            values = values.filter(\.isFavorite)
        case .group(let id):
            values = values.filter { $0.groupID == id }
        case .connectionProtocol(let kind):
            values = values.filter { $0.kind == kind }
        default:
            break
        }
        return ConnectionSearch.sort(values, by: app.router.sortOption)
    }

    var body: some View {
        @Bindable var router = app.router
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title.bold())
                Spacer()
                Picker("Sort", selection: $router.sortOption) {
                    Text("Name").tag(SortOption.name)
                    Text("Host").tag(SortOption.host)
                    Text("Protocol").tag(SortOption.protocolKind)
                    Text("Last Used").tag(SortOption.lastUsed)
                    Text("Created").tag(SortOption.created)
                }
                .frame(width: 150)
            }
            .padding()

            if displayedConnections.isEmpty {
                ContentUnavailableView(
                    app.router.searchText.isEmpty ? "No connections" : "No matches",
                    systemImage: "server.rack",
                    description: Text(app.router.searchText.isEmpty
                        ? "Create a connection or choose another group."
                        : "Try a name, host, tag, group, or protocol.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $router.selectedConnectionID) {
                    ForEach(displayedConnections) { connection in
                        ConnectionRow(connection: connection)
                            .tag(connection.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { connect(connection) }
                            .contextMenu { contextMenu(connection) }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("New Connection", systemImage: "plus") { app.router.newConnection() }
                    .help("New Connection (⌘N)")
                if let selected {
                    Button("Connect", systemImage: "play.fill") { connect(selected) }
                    Button("Edit", systemImage: "pencil") { app.router.edit(selected) }
                }
            }
        }
        .onSubmit {
            if let selected { connect(selected) }
        }
        .confirmationDialog(
            "Delete this connection?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deleteTarget {
                    perform { try app.library.deleteConnection(deleteTarget) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("The saved Keychain credential is not deleted.")
        }
        .alert(
            "Connection Operation Failed",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var selected: ConnectionProfile? {
        guard let id = app.router.selectedConnectionID else { return nil }
        return app.library.connections.first { $0.id == id }
    }

    private var title: String {
        switch filter {
        case .favorites: "Favorites"
        case .group(let id): app.library.groups.first { $0.id == id }?.name ?? "Group"
        case .connectionProtocol(let kind): kind.displayName
        default: "All Connections"
        }
    }

    @ViewBuilder
    private func contextMenu(_ connection: ConnectionProfile) -> some View {
        Button("Connect") { connect(connection) }
        Button("Edit") { app.router.edit(connection) }
        Button("Duplicate") { perform { _ = try app.library.duplicate(connection) } }
        Button(connection.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            perform { try app.library.toggleFavorite(connection) }
        }
        Menu("Move to Group") {
            Button("Ungrouped") { perform { try app.library.move(connection, to: nil) } }
            ForEach(app.library.groups) { group in
                Button(group.name) { perform { try app.library.move(connection, to: group.id) } }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { deleteTarget = connection }
    }

    private func connect(_ connection: ConnectionProfile) {
        app.workspace.open(connection)
        app.router.sidebarSelection = .workspace
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            operationError = Redactor.sanitize(error.localizedDescription)
        }
    }
}

private struct ConnectionRow: View {
    @Environment(AppContainer.self) private var app
    let connection: ConnectionProfile

    var body: some View {
        let endpoint = PortDisplayFormatter.endpoint(
            host: connection.host,
            port: connection.port
        )
        HStack(spacing: 12) {
            Image(systemName: connection.kind.systemImage)
                .frame(width: 24)
                .foregroundStyle(connection.kind.isEncrypted ? Color.accentColor : Color.orange)
                .accessibilityLabel(connection.kind.displayName)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(connection.name).fontWeight(.medium)
                    if connection.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    }
                }
                Text(verbatim: endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(verbatim: endpoint))
            }
            Spacer()
            Text(groupName).font(.caption).foregroundStyle(.secondary)
            ProtocolBadge(kind: connection.kind)
            ConnectionResultIcon(result: connection.lastResult)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var groupName: String {
        guard let id = connection.groupID else { return "Ungrouped" }
        return app.library.groups.first { $0.id == id }?.name ?? "Ungrouped"
    }
}
