import AppKit
import SwiftUI

struct FileTransferWorkspace: View {
    let tab: WorkspaceTab
    @State private var localFolder: URL?

    var body: some View {
        HSplitView {
            LocalFileBrowser(folder: $localFolder)
                .frame(minWidth: 280)
            RemoteFileBrowser(tab: tab, compact: false)
                .frame(minWidth: 420)
        }
    }
}

private struct LocalFileBrowser: View {
    @Binding var folder: URL?
    @State private var items: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(folder?.path(percentEncoded: false) ?? "Choose a local folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…", systemImage: "folder") { choose() }
            }
            .padding(10)
            Divider()
            if folder == nil {
                ContentUnavailableView(
                    "No local folder selected",
                    systemImage: "folder",
                    description: Text("Choose a folder to browse local files.")
                )
            } else {
                List(items, id: \.self) { url in
                    Label(url.lastPathComponent, systemImage: isDirectory(url) ? "folder.fill" : "doc")
                        .onTapGesture(count: 2) {
                            if isDirectory(url) {
                                folder = url
                                reload()
                            } else {
                                NSWorkspace.shared.open(url)
                            }
                        }
                }
            }
        }
        .onChange(of: folder) { _, _ in reload() }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            folder = panel.url
            reload()
        }
    }

    private func reload() {
        guard let folder else {
            items = []
            return
        }
        items = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ).sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) ?? []
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

struct RemoteFileBrowser: View {
    @Environment(AppContainer.self) private var app
    let tab: WorkspaceTab
    let compact: Bool

    @State private var selectedPath: String?
    @State private var showsNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: RemoteFileItem?
    @State private var renameValue = ""
    @State private var deleteTarget: RemoteFileItem?
    @State private var permissionTarget: RemoteFileItem?
    @State private var permissionValue = "0644"

    private var visibleItems: [RemoteFileItem] {
        app.settings.showHiddenFiles ? tab.remoteItems : tab.remoteItems.filter { !$0.name.hasPrefix(".") }
    }

    var body: some View {
        @Bindable var tab = tab
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Up", systemImage: "arrow.up") { goUp() }
                    .labelStyle(.iconOnly)
                    .disabled(tab.remotePath == "/")
                TextField("Remote path", text: $tab.remotePath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { app.workspace.refresh(tab) }
                Button("Refresh", systemImage: "arrow.clockwise") { app.workspace.refresh(tab) }
                    .labelStyle(.iconOnly)
                Menu {
                    Button("New Folder") { showsNewFolder = true }
                    Button("Upload Files or Folders…") { upload() }
                    if let selected {
                        Button("Download…") { download(selected) }
                        Button("Rename…") {
                            renameTarget = selected
                            renameValue = selected.name
                        }
                        if tab.sftpSession != nil {
                            Button("Change Permissions…") {
                                permissionTarget = selected
                                permissionValue = selected.permissions ?? "0644"
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { deleteTarget = selected }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(10)
            Divider()

            if visibleItems.isEmpty {
                ContentUnavailableView(
                    tab.state == .connected ? "Folder is empty" : "Remote files unavailable",
                    systemImage: "folder",
                    description: Text(tab.state == .connected ? tab.remotePath : "Connect to browse files.")
                )
            } else {
                Table(visibleItems, selection: $selectedPath) {
                    TableColumn("Name") { item in
                        Label(item.name, systemImage: item.type == .directory ? "folder.fill" : "doc")
                            .onTapGesture(count: 2) { open(item) }
                    }
                    TableColumn("Size") { item in
                        Text(item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—")
                    }
                    .width(80)
                    TableColumn("Permissions") { item in
                        permissionsCell(for: item)
                    }
                        .width(90)
                    TableColumn("Owner") { item in
                        ownerCell(for: item)
                    }
                    .width(100)
                    TableColumn("Modified") { item in
                        modifiedCell(for: item)
                    }
                        .width(100)
                }
                .contextMenu(forSelectionType: String.self) { selection in
                    if let path = selection.first,
                       let item = visibleItems.first(where: { $0.path == path }) {
                        Button("Download…") { download(item) }
                        Button("Rename…") {
                            renameTarget = item
                            renameValue = item.name
                        }
                        Button("Delete", role: .destructive) { deleteTarget = item }
                    }
                } primaryAction: { selection in
                    if let path = selection.first,
                       let item = visibleItems.first(where: { $0.path == path }) {
                        open(item)
                    }
                }
            }
        }
        .alert("New Remote Folder", isPresented: $showsNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createFolder() }
        }
        .alert(
            "Rename Remote Item",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Name", text: $renameValue)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { rename() }
        }
        .alert(
            "Change Permissions",
            isPresented: Binding(
                get: { permissionTarget != nil },
                set: { if !$0 { permissionTarget = nil } }
            )
        ) {
            TextField("Octal mode (for example 0644)", text: $permissionValue)
            Button("Cancel", role: .cancel) { permissionTarget = nil }
            Button("Apply") { changePermissions() }
        }
        .confirmationDialog(
            "Delete remote item?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget?.name ?? "")
        }
    }

    private var selected: RemoteFileItem? {
        guard let selectedPath else { return nil }
        return visibleItems.first { $0.path == selectedPath }
    }

    private func open(_ item: RemoteFileItem) {
        if item.type == .directory {
            tab.remotePath = item.path
            selectedPath = nil
            app.workspace.refresh(tab)
        } else {
            download(item)
        }
    }

    private func goUp() {
        let parent = (tab.remotePath as NSString).deletingLastPathComponent
        tab.remotePath = parent.isEmpty ? "/" : parent
        selectedPath = nil
        app.workspace.refresh(tab)
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return }
        let path = RemoteTransferService.join(tab.remotePath, name)
        Task {
            do {
                if let sftp = tab.sftpSession {
                    try await sftp.createDirectory(path: path)
                } else if let ftp = tab.ftpClient {
                    try await ftp.createDirectory(path: path)
                }
                app.workspace.refresh(tab)
            } catch {
                tab.error = RemoteHubError(.permissionDenied, message: "The folder could not be created.", technicalDetails: error.localizedDescription)
            }
        }
        newFolderName = ""
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let existing = Set(tab.remoteItems.map { $0.name.lowercased() })
        for localURL in panel.urls {
            var remotePath = RemoteTransferService.join(tab.remotePath, localURL.lastPathComponent)
            if existing.contains(localURL.lastPathComponent.lowercased()) {
                switch app.settings.overwriteBehavior {
                case .skip:
                    continue
                case .keepBoth:
                    remotePath = RemoteTransferService.uniqueRemotePath(
                        basePath: tab.remotePath,
                        name: localURL.lastPathComponent,
                        existingNames: existing
                    )
                case .ask:
                    tab.error = RemoteHubError(
                        .validation,
                        message: "\(localURL.lastPathComponent) already exists on the server.",
                        recoverySuggestion: "Choose Replace, Skip, or Keep Both in Transfer Settings, then retry."
                    )
                    continue
                case .replace:
                    break
                }
            }
            let sftp = tab.sftpSession
            let ftp = tab.ftpClient
            let destinationPath = remotePath
            app.transfers.enqueue(
                key: "upload:\(localURL.path)->\(destinationPath)",
                title: "Upload \(localURL.lastPathComponent)"
            ) { progress in
                try await RemoteTransferService.upload(
                    localURL: localURL,
                    to: destinationPath,
                    sftp: sftp,
                    ftp: ftp,
                    progress: progress
                )
            }
        }
    }

    private func permissionsCell(for item: RemoteFileItem) -> Text {
        Text(item.permissions ?? "—")
    }

    private func ownerCell(for item: RemoteFileItem) -> Text {
        let owner = [item.owner, item.group].compactMap { $0 }.joined(separator: ":")
        return Text(owner.isEmpty ? "—" : owner)
    }

    @ViewBuilder
    private func modifiedCell(for item: RemoteFileItem) -> some View {
        if let date = item.modifiedAt {
            Text(date, style: .date)
        } else {
            Text("—")
        }
    }

    private func download(_ item: RemoteFileItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let localURL = panel.url else { return }
        let sftp = tab.sftpSession
        let ftp = tab.ftpClient
        app.transfers.enqueue(
            key: "download:\(item.path)->\(localURL.path)",
            title: "Download \(item.name)"
        ) { progress in
            try await RemoteTransferService.download(
                item: item,
                to: localURL,
                sftp: sftp,
                ftp: ftp,
                progress: progress
            )
        }
    }

    private func rename() {
        guard let target = renameTarget else { return }
        let name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return }
        let destination = RemoteTransferService.join(tab.remotePath, name)
        Task {
            do {
                if let sftp = tab.sftpSession {
                    try await sftp.rename(from: target.path, to: destination)
                } else if let ftp = tab.ftpClient {
                    try await ftp.rename(from: target.path, to: destination)
                }
                app.workspace.refresh(tab)
            } catch {
                tab.error = RemoteHubError(.permissionDenied, message: "The remote item could not be renamed.", technicalDetails: error.localizedDescription)
            }
        }
        renameTarget = nil
    }

    private func deleteSelected() {
        guard let target = deleteTarget else { return }
        Task {
            do {
                if let sftp = tab.sftpSession {
                    if target.type == .directory {
                        try await sftp.removeDirectory(path: target.path)
                    } else {
                        try await sftp.removeFile(path: target.path)
                    }
                } else if let ftp = tab.ftpClient {
                    if target.type == .directory {
                        try await ftp.removeDirectory(path: target.path)
                    } else {
                        try await ftp.removeFile(path: target.path)
                    }
                }
                app.workspace.refresh(tab)
            } catch {
                tab.error = RemoteHubError(.permissionDenied, message: "The remote item could not be deleted.", technicalDetails: error.localizedDescription)
            }
        }
        deleteTarget = nil
    }

    private func changePermissions() {
        guard let target = permissionTarget,
              let mode = UInt32(permissionValue, radix: 8),
              mode <= 0o7777,
              let sftp = tab.sftpSession
        else { return }
        Task {
            do {
                try await sftp.setPermissions(path: target.path, mode: mode)
                app.workspace.refresh(tab)
            } catch {
                tab.error = RemoteHubError(.permissionDenied, message: "Permissions could not be changed.", technicalDetails: error.localizedDescription)
            }
        }
        permissionTarget = nil
    }
}
