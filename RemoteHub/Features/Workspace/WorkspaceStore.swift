import Foundation
import Observation

enum WorkspaceTabKind: Sendable {
    case ssh
    case files
    case rdp
}

@MainActor
@Observable
final class WorkspaceTab: Identifiable {
    let id = UUID()
    let connectionID: UUID
    let kind: WorkspaceTabKind
    var title: String
    var state: ConnectionState = .idle
    var error: RemoteHubError?
    var isSFTPPanelVisible = false
    var remotePath = "/"
    var remoteItems: [RemoteFileItem] = []
    var rdpExitStatus: Int32?

    @ObservationIgnored var connectionTask: Task<Void, Never>?
    @ObservationIgnored var sshSession: (any SSHSession)?
    @ObservationIgnored var sftpSession: (any SFTPSession)?
    @ObservationIgnored var ftpClient: (any FTPClient)?
    @ObservationIgnored var rdpHandle: (any RDPSessionHandle)?

    init(connection: ConnectionProfile) {
        connectionID = connection.id
        title = connection.name
        switch connection.kind {
        case .ssh: kind = .ssh
        case .sftp, .ftp, .ftpsExplicit, .ftpsImplicit: kind = .files
        case .rdp: kind = .rdp
        }
        isSFTPPanelVisible = connection.kind == .ssh && connection.protocolSettings.ssh.openSFTPPanelByDefault
        remotePath = switch connection.kind {
        case .ssh, .sftp: connection.protocolSettings.ssh.initialRemoteDirectory
        case .ftp, .ftpsExplicit, .ftpsImplicit: connection.protocolSettings.ftp.initialRemoteDirectory
        case .rdp: "/"
        }
    }
}

@MainActor
@Observable
final class WorkspaceStore {
    private(set) var tabs: [WorkspaceTab] = []
    var selectedTabID: UUID?

    private let connector: ConnectionConnector

    init(connector: ConnectionConnector) {
        self.connector = connector
    }

    func open(_ connection: ConnectionProfile) {
        let tab = WorkspaceTab(connection: connection)
        tabs.append(tab)
        selectedTabID = tab.id
        tab.connectionTask = Task { [weak connector, weak tab] in
            guard let connector, let tab else { return }
            await connector.connect(connection, into: tab)
        }
    }

    func duplicate(_ tab: WorkspaceTab, library: LibraryStore) {
        guard let connection = library.connections.first(where: { $0.id == tab.connectionID }) else { return }
        open(connection)
    }

    func reconnect(_ tab: WorkspaceTab, library: LibraryStore) {
        tab.connectionTask?.cancel()
        guard let connection = library.connections.first(where: { $0.id == tab.connectionID }) else { return }
        tab.error = nil
        tab.state = .reconnecting
        tab.connectionTask = Task { [weak connector, weak tab] in
            guard let connector, let tab else { return }
            await disconnect(tab)
            guard !Task.isCancelled else { return }
            tab.state = .reconnecting
            await connector.connect(connection, into: tab)
        }
    }

    func close(_ tab: WorkspaceTab) {
        tab.connectionTask?.cancel()
        Task { await disconnect(tab) }
        tabs.removeAll { $0.id == tab.id }
        if selectedTabID == tab.id {
            selectedTabID = tabs.last?.id
        }
    }

    func disconnect(_ tab: WorkspaceTab) async {
        await tab.sshSession?.disconnect()
        await tab.sftpSession?.disconnect()
        await tab.ftpClient?.disconnect()
        if let rdpHandle = tab.rdpHandle {
            rdpHandle.terminate()
            _ = await rdpHandle.waitForExit()
            if tab.rdpHandle?.id == rdpHandle.id {
                tab.rdpHandle = nil
            }
        }
        tab.state = .disconnected
    }

    @discardableResult
    func bringRDPToFront(_ tab: WorkspaceTab) -> Bool {
        tab.rdpHandle?.bringToFront() ?? false
    }

    func terminateRDP(_ tab: WorkspaceTab) async {
        guard let handle = tab.rdpHandle else { return }
        handle.terminate()
        _ = await handle.waitForExit()
    }

    func refresh(_ tab: WorkspaceTab) {
        tab.connectionTask = Task { [weak connector, weak tab] in
            guard let connector, let tab else { return }
            await connector.refreshFiles(in: tab)
        }
    }

    func test(_ connection: ConnectionProfile) async -> Result<Void, RemoteHubError> {
        let tab = WorkspaceTab(connection: connection)
        await connector.connect(connection, into: tab, recordsAttempt: false)
        defer { Task { await disconnect(tab) } }
        if let error = tab.error { return .failure(error) }
        return .success(())
    }
}
