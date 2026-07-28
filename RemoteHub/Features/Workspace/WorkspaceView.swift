import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            if app.workspace.tabs.isEmpty {
                ContentUnavailableView {
                    Label("No open sessions", systemImage: "rectangle.3.group")
                } description: {
                    Text("Double-click a saved connection to open it in a workspace tab.")
                } actions: {
                    Button("Browse Connections") {
                        app.router.sidebarSelection = .allConnections
                    }
                }
            } else {
                tabStrip
                Divider()
                if let tab = selectedTab {
                    tabContent(tab)
                }
            }
        }
        .navigationTitle("Workspace")
        .toolbar {
            if let tab = selectedTab {
                ToolbarItemGroup {
                    if tab.state == .connected {
                        if tab.kind == .rdp {
                            Button("Bring RDP Window to Front", systemImage: "macwindow.on.rectangle") {
                                _ = app.workspace.bringRDPToFront(tab)
                            }
                            Button("Terminate Session", systemImage: "stop.fill") {
                                Task { await app.workspace.terminateRDP(tab) }
                            }
                        } else {
                            Button("Disconnect", systemImage: "stop.fill") {
                                Task { await app.workspace.disconnect(tab) }
                            }
                        }
                    } else {
                        Button("Reconnect", systemImage: "arrow.clockwise") {
                            app.workspace.reconnect(tab, library: app.library)
                        }
                    }
                    if tab.kind == .ssh {
                        Button("Toggle SFTP", systemImage: "sidebar.right") {
                            toggleFiles(tab)
                        }
                    }
                }
            }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(app.workspace.tabs) { tab in
                    Button {
                        app.workspace.selectedTabID = tab.id
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(stateColor(tab.state))
                                .frame(width: 7, height: 7)
                            Text(tab.title).lineLimit(1)
                            Button {
                                app.workspace.close(tab)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close \(tab.title)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            app.workspace.selectedTabID == tab.id
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if tab.kind == .rdp, tab.state == .connected {
                            Button("Bring RDP Window to Front") {
                                _ = app.workspace.bringRDPToFront(tab)
                            }
                            Button("Terminate Session", role: .destructive) {
                                Task { await app.workspace.terminateRDP(tab) }
                            }
                            Divider()
                        }
                        Button("Reconnect") { app.workspace.reconnect(tab, library: app.library) }
                        Button("Duplicate Tab") { app.workspace.duplicate(tab, library: app.library) }
                        Button("Close Tab") { app.workspace.close(tab) }
                    }
                }
            }
            .padding(7)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func tabContent(_ tab: WorkspaceTab) -> some View {
        VStack(spacing: 0) {
            if let error = tab.error {
                ErrorBanner(error: error) { tab.error = nil }
                    .padding(10)
            }
            switch tab.state {
            case .connecting, .reconnecting:
                VStack(spacing: 14) {
                    ProgressView()
                    Text(tab.state == .connecting ? "Connecting…" : "Reconnecting…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                switch tab.kind {
                case .ssh:
                    sshWorkspace(tab)
                case .files:
                    FileTransferWorkspace(tab: tab)
                case .rdp:
                    RDPStatusView(tab: tab)
                }
            }
            if !app.transfers.records.isEmpty {
                Divider()
                TransferQueueView()
                    .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private func sshWorkspace(_ tab: WorkspaceTab) -> some View {
        if let session = tab.sshSession {
            if tab.isSFTPPanelVisible {
                HSplitView {
                    terminal(session, tab: tab)
                        .frame(minWidth: 420)
                    RemoteFileBrowser(tab: tab, compact: true)
                        .frame(minWidth: 330, idealWidth: 420)
                }
            } else {
                terminal(session, tab: tab)
            }
        } else if tab.state == .failed {
            ContentUnavailableView("SSH session unavailable", systemImage: "terminal")
        }
    }

    private func terminal(_ session: any SSHSession, tab: WorkspaceTab) -> some View {
        SwiftTermSessionView(
            session: session,
            fontName: app.settings.terminalFontName,
            fontSize: app.settings.terminalFontSize
        ) { title in
            if !title.isEmpty { tab.title = title }
        }
        .background(Color(nsColor: .black))
    }

    private var selectedTab: WorkspaceTab? {
        guard let id = app.workspace.selectedTabID else { return nil }
        return app.workspace.tabs.first { $0.id == id }
    }

    private func toggleFiles(_ tab: WorkspaceTab) {
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

    private func stateColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .failed: .red
        default: .secondary
        }
    }
}

private struct RDPStatusView: View {
    @Environment(AppContainer.self) private var app
    let tab: WorkspaceTab

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: tab.state == .connected ? "display.and.arrow.down" : "display.trianglebadge.exclamationmark")
                .font(.system(size: 54))
                .foregroundStyle(tab.state == .connected ? .green : .secondary)
            Text(tab.title).font(.title.bold())
            Text(statusText).foregroundStyle(.secondary)
            if let handle = tab.rdpHandle {
                Text("Started \(handle.startedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if tab.state == .connected {
                    Button("Bring RDP Window to Front") {
                        _ = app.workspace.bringRDPToFront(tab)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Terminate Session", role: .destructive) {
                        Task { await app.workspace.terminateRDP(tab) }
                    }
                }
                Button("Reconnect") {
                    app.workspace.reconnect(tab, library: app.library)
                }
                .disabled(tab.state == .connecting || tab.state == .reconnecting)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if tab.state == .connected { return "FreeRDP is running in an external window." }
        if let exit = tab.rdpExitStatus { return "FreeRDP ended with status \(exit)." }
        return "The RDP process is not running."
    }
}
