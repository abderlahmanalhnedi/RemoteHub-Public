import SwiftUI

struct SidebarView: View {
    @Environment(AppContainer.self) private var app
    @Binding var selection: SidebarSelection?
    @Binding var searchText: String
    @FocusState private var searchFocused: Bool
    @State private var showsNewGroup = false
    @State private var newGroupName = ""
    @State private var groupError: String?
    @State private var deleteGroupTarget: ConnectionGroup?
    @State private var operationError: String?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Dashboard", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.dashboard)
                Label("Favorites", systemImage: "star")
                    .badge(app.library.connections.filter(\.isFavorite).count)
                    .tag(SidebarSelection.favorites)
                Label("All Connections", systemImage: "server.rack")
                    .badge(app.library.connections.count)
                    .tag(SidebarSelection.allConnections)
            }

            Section("Groups") {
                ForEach(app.library.groups) { group in
                    Label(group.name, systemImage: "folder")
                        .badge(app.library.connections.filter { $0.groupID == group.id }.count)
                        .tag(SidebarSelection.group(group.id))
                        .contextMenu {
                            Button("Delete Group", role: .destructive) {
                                deleteGroupTarget = group
                            }
                        }
                }
                Button("New Group", systemImage: "folder.badge.plus") {
                    showsNewGroup = true
                }
                .buttonStyle(.plain)
            }

            Section("Protocols") {
                ForEach(ConnectionKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.systemImage)
                        .badge(app.library.connections.filter { $0.kind == kind }.count)
                        .tag(SidebarSelection.connectionProtocol(kind))
                }
            }

            Section {
                Label("Credentials", systemImage: "key")
                    .tag(SidebarSelection.credentials)
                Label("Workspace", systemImage: "rectangle.3.group")
                    .badge(app.workspace.tabs.count)
                    .tag(SidebarSelection.workspace)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
        }
        .safeAreaInset(edge: .top) {
            TextField("Search connections", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding([.horizontal, .top], 10)
                .padding(.bottom, 4)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        .onReceive(NotificationCenter.default.publisher(for: .remoteHubFocusSearch)) { _ in
            searchFocused = true
        }
        .alert("New Group", isPresented: $showsNewGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) {
                newGroupName = ""
                groupError = nil
            }
            Button("Create") { createGroup() }
        } message: {
            Text(groupError ?? "Connections can be moved here from their context menu.")
        }
        .confirmationDialog(
            "Delete this group?",
            isPresented: Binding(
                get: { deleteGroupTarget != nil },
                set: { if !$0 { deleteGroupTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                guard let group = deleteGroupTarget else { return }
                do {
                    try app.library.deleteGroup(group)
                } catch {
                    operationError = Redactor.sanitize(error.localizedDescription)
                }
                deleteGroupTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteGroupTarget = nil }
        } message: {
            Text("Connections in this group will move to Ungrouped.")
        }
        .alert(
            "Group Operation Failed",
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

    private func createGroup() {
        do {
            try app.library.saveGroup(ConnectionGroup(name: newGroupName))
            newGroupName = ""
            groupError = nil
        } catch {
            groupError = Redactor.sanitize(error.localizedDescription)
            showsNewGroup = true
        }
    }
}
