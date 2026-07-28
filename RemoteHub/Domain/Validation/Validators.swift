import Foundation

enum ValidationIssue: Equatable, Sendable {
    case required(String)
    case tooLong(field: String, maximum: Int)
    case invalidHost
    case invalidPort
    case duplicateGroup
    case invalidUsername
    case invalidResolution
    case unreadablePrivateKey

    var message: String {
        switch self {
        case .required(let field): "\(field) is required."
        case .tooLong(let field, let maximum): "\(field) must be \(maximum) characters or fewer."
        case .invalidHost: "Enter a DNS name, IPv4 address, or IPv6 address without a URL, path, or credentials."
        case .invalidPort: "Port must be between 1 and 65535."
        case .duplicateGroup: "A group with this name already exists."
        case .invalidUsername: "A username is required for this authentication method."
        case .invalidResolution: "Custom resolution must be between 320×200 and 16384×16384."
        case .unreadablePrivateKey: "The selected private key does not exist or is not readable."
        }
    }
}

enum Validators {
    static func connectionName(_ value: String) -> [ValidationIssue] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [.required("Name")] }
        if trimmed.count > 120 { return [.tooLong(field: "Name", maximum: 120)] }
        return []
    }

    static func host(_ value: String) -> [ValidationIssue] {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return [.required("Host")] }
        guard host.count <= 253,
              !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !host.contains("://"),
              !host.contains("@"),
              !host.contains("/"),
              !host.contains("\\"),
              !host.contains("?"),
              !host.contains("#")
        else { return [.invalidHost] }

        if isIPv4(host) || isIPv6(host) || isDNSName(host) { return [] }
        return [.invalidHost]
    }

    static func port(_ value: Int) -> [ValidationIssue] {
        (1...65_535).contains(value) ? [] : [.invalidPort]
    }

    static func username(_ value: String, authenticationType: AuthenticationType) -> [ValidationIssue] {
        if authenticationType == .anonymousFTP || authenticationType == .askEveryTime { return [] }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [.invalidUsername] : []
    }

    static func privateKey(url: URL) -> [ValidationIssue] {
        FileManager.default.isReadableFile(atPath: url.path) ? [] : [.unreadablePrivateKey]
    }

    static func rdpResolution(dynamic: Bool, width: Int, height: Int) -> [ValidationIssue] {
        guard !dynamic else { return [] }
        return (320...16_384).contains(width) && (200...16_384).contains(height) ? [] : [.invalidResolution]
    }

    static func groupName(_ value: String, existingNames: [String], excluding: String? = nil) -> [ValidationIssue] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [.required("Group name")] }
        let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let excluded = excluding?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let duplicate = existingNames.contains {
            let candidate = $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return candidate == normalized && candidate != excluded
        }
        return duplicate ? [.duplicateGroup] : []
    }

    private static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber) && (Int($0) ?? -1) <= 255
        }
    }

    private static func isIPv6(_ value: String) -> Bool {
        var address = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    private static func isDNSName(_ value: String) -> Bool {
        guard !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard !label.isEmpty, label.count <= 63,
                  label.first != "-", label.last != "-"
            else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}

struct PortSelectionState: Equatable, Sendable {
    private(set) var kind: ConnectionKind
    private(set) var port: Int
    private(set) var wasManuallyEdited: Bool

    init(kind: ConnectionKind, port: Int? = nil, wasManuallyEdited: Bool = false) {
        self.kind = kind
        self.port = port ?? kind.defaultPort
        self.wasManuallyEdited = wasManuallyEdited
    }

    mutating func setPort(_ value: Int) {
        port = value
        wasManuallyEdited = true
    }

    mutating func changeKind(to newKind: ConnectionKind) {
        kind = newKind
        if !wasManuallyEdited {
            port = newKind.defaultPort
        }
    }
}
