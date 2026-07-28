import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let appearance = "appearance"
        static let terminalFontName = "terminalFontName"
        static let terminalFontSize = "terminalFontSize"
        static let showHiddenFiles = "showHiddenFiles"
        static let confirmDestructiveActions = "confirmDestructiveActions"
        static let overwriteBehavior = "overwriteBehavior"
        static let concurrentTransfers = "concurrentTransfers"
        static let freeRDPPath = "freeRDPPath"
        static let rdpPreflightTimeoutSeconds = "rdpPreflightTimeoutSeconds"
    }

    private let defaults: UserDefaults

    var appearance: AppearancePreference { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    var terminalFontName: String { didSet { defaults.set(terminalFontName, forKey: Key.terminalFontName) } }
    var terminalFontSize: Double { didSet { defaults.set(terminalFontSize, forKey: Key.terminalFontSize) } }
    var showHiddenFiles: Bool { didSet { defaults.set(showHiddenFiles, forKey: Key.showHiddenFiles) } }
    var confirmDestructiveActions: Bool { didSet { defaults.set(confirmDestructiveActions, forKey: Key.confirmDestructiveActions) } }
    var overwriteBehavior: OverwriteBehavior { didSet { defaults.set(overwriteBehavior.rawValue, forKey: Key.overwriteBehavior) } }
    var concurrentTransfers: Int { didSet { defaults.set(concurrentTransfers, forKey: Key.concurrentTransfers) } }
    var freeRDPPath: String { didSet { defaults.set(freeRDPPath, forKey: Key.freeRDPPath) } }
    var rdpPreflightTimeoutSeconds: Int {
        didSet { defaults.set(rdpPreflightTimeoutSeconds, forKey: Key.rdpPreflightTimeoutSeconds) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        terminalFontName = defaults.string(forKey: Key.terminalFontName) ?? "SF Mono"
        terminalFontSize = defaults.object(forKey: Key.terminalFontSize) as? Double ?? 13
        showHiddenFiles = defaults.object(forKey: Key.showHiddenFiles) as? Bool ?? false
        confirmDestructiveActions = defaults.object(forKey: Key.confirmDestructiveActions) as? Bool ?? true
        overwriteBehavior = OverwriteBehavior(rawValue: defaults.string(forKey: Key.overwriteBehavior) ?? "") ?? .ask
        let storedConcurrency = defaults.object(forKey: Key.concurrentTransfers) as? Int
        concurrentTransfers = min(8, max(1, storedConcurrency ?? AppConstants.defaultTransferConcurrency))
        freeRDPPath = defaults.string(forKey: Key.freeRDPPath) ?? ""
        let storedRDPTimeout = defaults.object(forKey: Key.rdpPreflightTimeoutSeconds) as? Int
        rdpPreflightTimeoutSeconds = min(15, max(2, storedRDPTimeout ?? 5))
    }

    var colorScheme: ColorSchemePreference {
        switch appearance {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ColorSchemePreference {
    case system
    case light
    case dark
}
