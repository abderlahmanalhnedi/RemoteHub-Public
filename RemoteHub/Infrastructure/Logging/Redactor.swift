import Foundation

enum Redactor {
    private static let credentialURL = try? NSRegularExpression(
        pattern: #"(?i)([a-z][a-z0-9+.-]*://)([^/\s:@]+):([^@\s/]+)@"#
    )
    private static let passwordAssignment = try? NSRegularExpression(
        pattern: #"(?i)\b(password|passwd|passphrase|token)\s*[:=]\s*[^\s,;]+"#
    )
    private static let sensitiveFreeRDPArgument = try? NSRegularExpression(
        pattern: #"(?i)(?:^|\s)(/(?:p|u|d):|--(?:password|username|domain)(?:=|\s+))(?:"[^"]*"|'[^']*'|[^\s]+)"#
    )

    static func sanitize(_ input: String) -> String {
        sanitize(input, sensitiveValues: [])
    }

    static func sanitize(_ input: String, sensitiveValues: [String]) -> String {
        var value = input
        for sensitiveValue in sensitiveValues where !sensitiveValue.isEmpty {
            value = value.replacingOccurrences(of: sensitiveValue, with: "<redacted>")
        }
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        value = credentialURL?.stringByReplacingMatches(
            in: value,
            range: fullRange,
            withTemplate: "$1<redacted>:<redacted>@"
        ) ?? value
        let updatedRange = NSRange(value.startIndex..<value.endIndex, in: value)
        value = passwordAssignment?.stringByReplacingMatches(
            in: value,
            range: updatedRange,
            withTemplate: "$1=<redacted>"
        ) ?? value
        let argumentRange = NSRange(value.startIndex..<value.endIndex, in: value)
        value = sensitiveFreeRDPArgument?.stringByReplacingMatches(
            in: value,
            range: argumentRange,
            withTemplate: " $1<redacted>"
        ) ?? value
        return value
    }

    static func diagnosticSummary(
        protocolKind: ConnectionKind?,
        category: RemoteHubError.Category?,
        includeHost: String? = nil
    ) -> String {
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif

        var lines = [
            "Application: \(AppConstants.productName)",
            "Version: 1.0.0",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(architecture)",
            "SwiftTerm: 1.14.0",
            "Citadel: 0.12.1",
            "Protocol: \(protocolKind?.displayName ?? "Not selected")",
            "Error category: \(category?.rawValue ?? "none")"
        ]
        if let includeHost {
            lines.append("Host (user opted in): \(sanitize(includeHost))")
        }
        return lines.joined(separator: "\n")
    }
}
