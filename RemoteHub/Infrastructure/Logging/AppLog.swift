import OSLog

enum AppLog {
    private static let subsystem = AppConstants.bundleIdentifier

    static let app = Logger(subsystem: subsystem, category: "app")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let ssh = Logger(subsystem: subsystem, category: "ssh")
    static let sftp = Logger(subsystem: subsystem, category: "sftp")
    static let ftp = Logger(subsystem: subsystem, category: "ftp")
    static let rdp = Logger(subsystem: subsystem, category: "rdp")
    static let transfers = Logger(subsystem: subsystem, category: "transfers")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
