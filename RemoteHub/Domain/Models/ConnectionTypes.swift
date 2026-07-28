import Foundation

enum ConnectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ssh
    case sftp
    case ftp
    case ftpsExplicit
    case ftpsImplicit
    case rdp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ssh: "SSH"
        case .sftp: "SFTP"
        case .ftp: "FTP"
        case .ftpsExplicit: "FTPS (Explicit)"
        case .ftpsImplicit: "FTPS (Implicit)"
        case .rdp: "RDP"
        }
    }

    var shortName: String {
        switch self {
        case .ftpsExplicit, .ftpsImplicit: "FTPS"
        default: displayName
        }
    }

    var systemImage: String {
        switch self {
        case .ssh: "terminal"
        case .sftp, .ftp, .ftpsExplicit, .ftpsImplicit: "folder.badge.gearshape"
        case .rdp: "display"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ssh, .sftp: 22
        case .ftp, .ftpsExplicit: 21
        case .ftpsImplicit: 990
        case .rdp: 3389
        }
    }

    var isEncrypted: Bool {
        self != .ftp
    }
}

enum AuthenticationType: String, Codable, CaseIterable, Identifiable, Sendable {
    case usernamePassword
    case sshPrivateKey
    case sshPrivateKeyWithPassphrase
    case sshAgent
    case anonymousFTP
    case askEveryTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usernamePassword: "Username and Password"
        case .sshPrivateKey: "SSH Private Key"
        case .sshPrivateKeyWithPassphrase: "SSH Private Key with Passphrase"
        case .sshAgent: "SSH Agent"
        case .anonymousFTP: "Anonymous FTP"
        case .askEveryTime: "Ask Every Time"
        }
    }
}

enum ConnectionResult: String, Codable, CaseIterable, Sendable {
    case never
    case success
    case failure
    case cancelled
}

enum ConnectionState: String, Codable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnected
    case failed
}

enum AttemptOutcome: String, Codable, Sendable {
    case success
    case failure
    case cancelled
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum OverwriteBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case ask
    case replace
    case skip
    case keepBoth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ask: "Ask"
        case .replace: "Replace"
        case .skip: "Skip"
        case .keepBoth: "Keep Both"
        }
    }
}

enum SortOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    case host
    case protocolKind
    case lastUsed
    case created

    var id: String { rawValue }
}
