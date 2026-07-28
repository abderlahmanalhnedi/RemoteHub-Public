import Foundation

typealias TransferProgressHandler = @Sendable (TransferProgress) -> Void

struct TransferProgress: Equatable, Sendable {
    let bytesTransferred: Int64
    let totalBytes: Int64?
    let bytesPerSecond: Double
}

struct RemoteFileItem: Identifiable, Equatable, Sendable {
    enum ItemType: String, Codable, Sendable {
        case file
        case directory
        case symbolicLink
    }

    let id: String
    let name: String
    let path: String
    let type: ItemType
    let size: Int64?
    let permissions: String?
    let owner: String?
    let group: String?
    let modifiedAt: Date?
    let symbolicLinkTarget: String?

    init(
        name: String,
        path: String,
        type: ItemType,
        size: Int64? = nil,
        permissions: String? = nil,
        owner: String? = nil,
        group: String? = nil,
        modifiedAt: Date? = nil,
        symbolicLinkTarget: String? = nil
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.type = type
        self.size = size
        self.permissions = permissions
        self.owner = owner
        self.group = group
        self.modifiedAt = modifiedAt
        self.symbolicLinkTarget = symbolicLinkTarget
    }
}

enum SSHAuthentication: Sendable {
    case password(username: String, password: String)
    case privateKey(username: String, fileURL: URL, passphrase: String?)
    case agent(username: String)
}

struct SSHConnectionConfiguration: Sendable {
    let host: String
    let port: Int
    let authentication: SSHAuthentication
    let terminalType: String
    let timeoutSeconds: Int
    let keepaliveSeconds: Int
    let opensInteractiveShell: Bool
}

protocol SSHTransport: Sendable {
    func connect(configuration: SSHConnectionConfiguration) async throws -> any SSHSession
}

protocol SSHSession: AnyObject, Sendable {
    var output: AsyncThrowingStream<Data, Error> { get }
    func send(_ data: Data) async throws
    func resize(columns: Int, rows: Int) async throws
    func openSFTP() async throws -> any SFTPSession
    func disconnect() async
}

protocol SFTPSession: AnyObject, Sendable {
    func list(path: String) async throws -> [RemoteFileItem]
    func createDirectory(path: String) async throws
    func rename(from: String, to: String) async throws
    func removeFile(path: String) async throws
    func removeDirectory(path: String) async throws
    func download(remotePath: String, to localURL: URL, progress: TransferProgressHandler?) async throws
    func upload(localURL: URL, to remotePath: String, progress: TransferProgressHandler?) async throws
    func setPermissions(path: String, mode: UInt32) async throws
    func disconnect() async
}

struct FTPConnectionConfiguration: Sendable {
    let kind: ConnectionKind
    let host: String
    let port: Int
    let username: String
    let password: String?
    let passiveMode: Bool
    let verifyTLSCertificate: Bool
    let timeoutSeconds: Int
}

protocol FTPClient: Sendable {
    func connect(configuration: FTPConnectionConfiguration) async throws
    func list(path: String) async throws -> [RemoteFileItem]
    func createDirectory(path: String) async throws
    func rename(from: String, to: String) async throws
    func removeFile(path: String) async throws
    func removeDirectory(path: String) async throws
    func upload(localURL: URL, to remotePath: String, progress: TransferProgressHandler?) async throws
    func download(remotePath: String, to localURL: URL, progress: TransferProgressHandler?) async throws
    func disconnect() async
}

enum RDPInstallationStatus: Equatable, Sendable {
    case available(RDPInstallation)
    case missing
    case incompatible(path: String, reason: String)
}

enum RDPInstallationSource: String, Equatable, Sendable {
    case bundled
    case customOverride
    case legacyDevelopment
}

struct RDPInstallation: Equatable, Sendable {
    let executableURL: URL
    let versionDescription: String
    let supportsSafePasswordInput: Bool
    let requiresXQuartz: Bool
    let source: RDPInstallationSource

    init(
        executableURL: URL,
        versionDescription: String,
        supportsSafePasswordInput: Bool,
        requiresXQuartz: Bool,
        source: RDPInstallationSource = .legacyDevelopment
    ) {
        self.executableURL = executableURL
        self.versionDescription = versionDescription
        self.supportsSafePasswordInput = supportsSafePasswordInput
        self.requiresXQuartz = requiresXQuartz
        self.source = source
    }
}

struct RDPConnectionConfiguration: Sendable {
    let host: String
    let port: Int
    let username: String
    let domain: String?
    let settings: RDPSettings
    let customExecutablePath: String?
    let preflightTimeoutSeconds: TimeInterval

    init(
        host: String,
        port: Int,
        username: String,
        domain: String?,
        settings: RDPSettings,
        customExecutablePath: String? = nil,
        preflightTimeoutSeconds: TimeInterval = 5
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.domain = domain
        self.settings = settings
        self.customExecutablePath = customExecutablePath
        self.preflightTimeoutSeconds = preflightTimeoutSeconds
    }
}

protocol SecretProvider: Sendable {
    func password() async throws -> String?
}

enum RDPProcessTerminationReason: Equatable, Sendable {
    case exited
    case uncaughtSignal
}

struct RDPProcessTermination: Equatable, Sendable {
    let exitCode: Int32
    let reason: RDPProcessTerminationReason
    let standardOutput: Data
    let standardError: Data
    let wasUserInitiated: Bool
}

protocol RDPSessionHandle: AnyObject, Sendable {
    var id: UUID { get }
    var processIdentifier: Int32 { get }
    var startedAt: Date { get }
    var isRunning: Bool { get }
    func waitForExit() async -> RDPProcessTermination
    @discardableResult func bringToFront() -> Bool
    func terminate()
}

protocol RDPLaunching: Sendable {
    func detectInstallation() async -> RDPInstallationStatus
    func launch(
        sessionIdentifier: UUID,
        configuration: RDPConnectionConfiguration,
        secretProvider: any SecretProvider
    ) async throws -> any RDPSessionHandle
}
