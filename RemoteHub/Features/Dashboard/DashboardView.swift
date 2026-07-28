import SwiftUI

struct DashboardView: View {
    @Environment(AppContainer.self) private var app

    private var favorites: [ConnectionProfile] {
        app.library.connections.filter(\.isFavorite)
    }

    private var recent: [ConnectionProfile] {
        app.library.connections
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if app.library.connections.isEmpty {
                    emptyState
                } else {
                    protocolCounts
                    favoritesSection
                    recentSection
                    failuresSection
                }
            }
            .padding(26)
        }
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("RemoteHub").font(.largeTitle.bold())
                Text("Your local, private connection workspace")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("New Connection", systemImage: "plus") {
                app.router.newConnection()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: [.command])
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No connections yet", systemImage: "server.rack")
        } description: {
            Text("Add a server once, link a secure credential, and connect from here later.")
        } actions: {
            Button("Create Connection") { app.router.newConnection() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
    }

    private var protocolCounts: some View {
        HStack(spacing: 12) {
            ForEach(ConnectionKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: kind.systemImage)
                        .foregroundStyle(Color.accentColor)
                    Text("\(app.library.connections.filter { $0.kind == kind }.count)")
                        .font(.title2.bold())
                    Text(kind.shortName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites").font(.title2.bold())
            if favorites.isEmpty {
                Text("Favorite connections appear here.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(favorites) { connection in
                        FavoriteCard(connection: connection)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Used").font(.title2.bold())
            if recent.isEmpty {
                Text("Successful connections will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recent) { connection in
                    Button {
                        connect(connection)
                    } label: {
                        HStack {
                            ProtocolBadge(kind: connection.kind)
                            VStack(alignment: .leading) {
                                Text(connection.name).fontWeight(.medium)
                                Text(connection.host).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let date = connection.lastUsedAt {
                                Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "arrow.right.circle")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var failuresSection: some View {
        let failures = app.library.connections.filter { $0.lastResult == .failure }
        if !failures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last Failed Connections").font(.title2.bold())
                ForEach(failures) { connection in
                    Label("\(connection.name) — \(connection.host)", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func connect(_ connection: ConnectionProfile) {
        app.workspace.open(connection)
        app.router.sidebarSelection = .workspace
    }
}

private struct FavoriteCard: View {
    @Environment(AppContainer.self) private var app
    let connection: ConnectionProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProtocolBadge(kind: connection.kind)
                Spacer()
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
            Text(connection.name).font(.headline)
            Text(connection.host).foregroundStyle(.secondary)
            Text(groupName).font(.caption).foregroundStyle(.secondary)
            HStack {
                if let last = connection.lastUsedAt {
                    Text("Used \(last, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect") {
                    app.workspace.open(connection)
                    app.router.sidebarSelection = .workspace
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private var groupName: String {
        guard let id = connection.groupID else { return "Ungrouped" }
        return app.library.groups.first { $0.id == id }?.name ?? "Ungrouped"
    }
}
