import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppContainer.self) private var app
    @State private var showsTransfers = false

    var body: some View {
        @Bindable var router = app.router
        NavigationSplitView {
            SidebarView(
                selection: $router.sidebarSelection,
                searchText: $router.searchText
            )
        } detail: {
            detail(for: router.sidebarSelection)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Connection", systemImage: "plus") { router.newConnection() }
                    .help("New Connection (⌘N)")
                Button("Transfers", systemImage: "arrow.up.arrow.down.circle") {
                    showsTransfers.toggle()
                }
                .badge(app.transfers.records.filter { $0.status == .running }.count)
                .popover(isPresented: $showsTransfers) {
                    TransferQueueView()
                        .environment(app)
                        .frame(width: 430, height: 360)
                }
                Button("Settings", systemImage: "gearshape") {
                    router.sidebarSelection = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .sheet(isPresented: $router.showsNewConnection) {
            ConnectionEditorView(connection: nil)
                .environment(app)
                .modelContainer(app.modelContainer)
        }
        .sheet(
            isPresented: Binding(
                get: { router.connectionEditorID != nil },
                set: { if !$0 { router.connectionEditorID = nil } }
            )
        ) {
            if let id = router.connectionEditorID,
               let connection = app.library.connections.first(where: { $0.id == id }) {
                ConnectionEditorView(connection: connection)
                    .environment(app)
                    .modelContainer(app.modelContainer)
            }
        }
        .sheet(isPresented: $router.showsNewCredential) {
            CredentialEditorView(credential: nil)
                .environment(app)
                .modelContainer(app.modelContainer)
        }
        .sheet(
            isPresented: Binding(
                get: { router.credentialEditorID != nil },
                set: { if !$0 { router.credentialEditorID = nil } }
            )
        ) {
            if let id = router.credentialEditorID,
               let credential = app.library.credentials.first(where: { $0.id == id }) {
                CredentialEditorView(credential: credential)
                    .environment(app)
                    .modelContainer(app.modelContainer)
            }
        }
        .modifier(PromptSheets())
        .onReceive(NotificationCenter.default.publisher(for: .remoteHubNewConnection)) { _ in
            router.newConnection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteHubCloseTab)) { _ in
            guard let tab = selectedTab else { return }
            app.workspace.close(tab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteHubReconnect)) { _ in
            guard let tab = selectedTab else { return }
            if tab.kind == .files {
                app.workspace.refresh(tab)
            } else {
                app.workspace.reconnect(tab, library: app.library)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteHubToggleFiles)) { _ in
            guard let tab = selectedTab, tab.kind == .ssh else { return }
            tab.isSFTPPanelVisible.toggle()
            if tab.isSFTPPanelVisible, tab.sftpSession == nil {
                Task {
                    do {
                        tab.sftpSession = try await tab.sshSession?.openSFTP()
                        app.workspace.refresh(tab)
                    } catch {
                        tab.error = RemoteHubError(
                            .unknown,
                            message: "The SFTP panel could not be opened.",
                            technicalDetails: error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detail(for selection: SidebarSelection?) -> some View {
        switch selection {
        case .dashboard, .none:
            DashboardView()
        case .favorites, .allConnections, .group, .connectionProtocol:
            ConnectionLibraryView(filter: selection)
        case .credentials:
            CredentialsView()
        case .workspace:
            WorkspaceView()
        case .settings:
            SettingsView()
        }
    }

    private var selectedTab: WorkspaceTab? {
        guard let id = app.workspace.selectedTabID else { return nil }
        return app.workspace.tabs.first { $0.id == id }
    }
}
