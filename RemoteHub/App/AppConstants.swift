import Foundation

enum AppConstants {
    static let productName = "RemoteHub"
    static let bundleIdentifier = "com.alhnedi.RemoteHub"
    static let keychainService = "\(bundleIdentifier).credentials"
    static let exportSchemaVersion = 1
    static let maximumConnectionAttempts = 100
    static let defaultTransferConcurrency = 3
}
