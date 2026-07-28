# Dashboard

The Dashboard is RemoteHub's starting view. Select **Dashboard** in the
sidebar at any time to return to it.

## Use the Dashboard

1. Select **Dashboard** in the sidebar.
2. Review the saved-profile counters, favorites, recent successful
   connections, and latest failed results.
3. Select a favorite or recent profile to open a new Workspace tab, or use
   **Create Connection**/**New Connection** when the library is empty.

## Empty state

When the library has no connections, the Dashboard shows **No connections
yet** and a **Create Connection** action. The header's **New Connection**
button and Command-N open the same editor.

## Protocol counters

Once at least one connection exists, the top row counts saved profiles for
each supported connection kind:

- SSH
- SFTP
- FTP
- FTPS (Explicit)
- FTPS (Implicit)
- RDP

These are profile counts, not active-session counts and not connectivity
health checks. Select a protocol in the sidebar to open the Connection Library
filtered to that protocol.

## Favorites

Profiles marked as favorites appear as cards. Each card shows:

- protocol;
- saved connection name and host;
- group, or **Ungrouped**;
- relative last-used time when available; and
- a **Connect** button.

Use a favorite for a profile you open regularly. Favorites remain ordinary
connection profiles and do not receive different trust or credential rules.
Add or remove the favorite state from a connection's context menu in the
[Connection Library](connections.md).

## Recently Used

The **Recently Used** section shows up to eight profiles ordered by their most
recent successful connection. RemoteHub updates `lastUsedAt` only after a
successful recorded attempt. Selecting a row immediately opens a new
workspace tab and starts the connection flow.

A failed or cancelled attempt updates the profile's last-result indicator but
does not make that attempt the profile's successful last-used time.

## Last Failed Connections

If a profile's most recent recorded result is a failure, the Dashboard lists
its connection name and host under **Last Failed Connections**. This section
is a quick indicator, not a full log:

- it does not display credentials or passwords;
- it does not show the stored attempt's error category; and
- it does not provide a detailed historical timeline.

Open the profile again to reproduce and inspect the current error banner.
Use **Show Details** and **Copy Diagnostics** as described in
[Troubleshooting](troubleshooting.md).

Connection-attempt records retain the connection identifier, start and end
timestamps, outcome, and an optional error category. They do not retain the
error text or credentials. The library keeps at most 100 attempt records.

## Moving to connections and workspaces

- Select **All Connections**, a group, a favorite filter, or a protocol in the
  sidebar to browse and manage saved profiles.
- Select **Connect** on a favorite or a recent item to create a new Workspace
  tab.
- Select **Workspace** to return to existing tabs. The badge beside Workspace
  is the number of open tabs, not the number of connected sessions.

## Privacy guidance

The Dashboard renders saved names and hosts directly. Use neutral profile
names when screen sharing, and avoid recording the Dashboard if its metadata
identifies sensitive systems. Tags and notes are searchable library metadata
but are not displayed on Dashboard cards.

## Current limitations

- The Dashboard does not expose a complete connection-attempt history.
- Failed connection information is limited to the profile name and host.
- Protocol counters do not test endpoint availability.
- Dashboard population and navigation are implemented, but the broader
  end-to-end dashboard workflow still requires manual verification.

## Evidence

- [`DashboardView.swift`](../../RemoteHub/Features/Dashboard/DashboardView.swift)
- [`SidebarView.swift`](../../RemoteHub/Features/Connections/SidebarView.swift)
- [`LibraryStore.swift`](../../RemoteHub/Infrastructure/Persistence/LibraryStore.swift)
