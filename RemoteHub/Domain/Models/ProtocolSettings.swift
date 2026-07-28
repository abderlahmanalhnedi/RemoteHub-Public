import Foundation

struct SSHSettings: Codable, Equatable, Sendable {
    var initialRemoteDirectory = "~"
    var terminalType = "xterm-256color"
    var keepaliveSeconds = 30
    var autoReconnect = false
    var connectTimeoutSeconds = 15
    var jumpHostConnectionID: UUID?
    var openSFTPPanelByDefault = false
    var legacyAlgorithmOverrides: [String] = []
}

enum FTPSMode: String, Codable, CaseIterable, Sendable {
    case none
    case explicit
    case implicit
}

struct FTPSettings: Codable, Equatable, Sendable {
    var passiveMode = true
    var mode: FTPSMode = .none
    var initialRemoteDirectory = "/"
    var verifyTLSCertificate = true
    var plainFTPWarningAcknowledged = false
}

enum RDPDisplayMode: String, Codable, CaseIterable, Sendable {
    case windowed
    case fullScreen
}

enum RDPNetworkProfile: String, Codable, CaseIterable, Sendable {
    case autoDetect
    case modem
    case broadbandLow
    case broadbandHigh
    case wan
    case lan
}

enum RDPCertificatePolicy: String, Codable, CaseIterable, Sendable {
    case prompt
    case trustOnFirstUse
    case ignore
}

struct RDPSettings: Codable, Equatable, Sendable {
    var displayMode: RDPDisplayMode = .windowed
    var dynamicResolution = true
    var width = 1440
    var height = 900
    var multiMonitor = false
    var clipboard = true
    var audio = true
    var microphone = false
    var redirectDrive = false
    var redirectedFolderBookmark: Data?
    var networkProfile: RDPNetworkProfile = .autoDetect
    var adminSession = false
    var certificatePolicy: RDPCertificatePolicy = .prompt
}

struct ProtocolSettings: Codable, Equatable, Sendable {
    static let version = 1

    var schemaVersion = version
    var ssh = SSHSettings()
    var ftp = FTPSettings()
    var rdp = RDPSettings()

    static var `default`: ProtocolSettings { ProtocolSettings() }
}
