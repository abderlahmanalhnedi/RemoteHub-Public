import Foundation

enum ConnectionSearch {
    static func filter(
        _ connections: [ConnectionProfile],
        query: String,
        groups: [ConnectionGroup]
    ) -> [ConnectionProfile] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return connections }
        let groupNames = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, normalized($0.name)) })

        return connections.filter { connection in
            let values = [
                connection.name,
                connection.host,
                connection.kind.displayName,
                groupNames[connection.groupID ?? UUID()] ?? ""
            ] + connection.tags
            return values.contains { normalized($0).contains(needle) }
        }
    }

    static func sort(_ connections: [ConnectionProfile], by option: SortOption) -> [ConnectionProfile] {
        connections.sorted { left, right in
            switch option {
            case .name:
                return localized(left.name, before: right.name)
            case .host:
                return localized(left.host, before: right.host)
            case .protocolKind:
                if left.kind == right.kind { return localized(left.name, before: right.name) }
                return left.kind.displayName < right.kind.displayName
            case .lastUsed:
                return (left.lastUsedAt ?? .distantPast) > (right.lastUsedAt ?? .distantPast)
            case .created:
                return left.createdAt > right.createdAt
            }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func localized(_ left: String, before right: String) -> Bool {
        left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }
}
