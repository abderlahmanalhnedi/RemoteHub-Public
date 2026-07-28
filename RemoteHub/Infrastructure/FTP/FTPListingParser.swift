import Foundation

enum FTPListingParser {
    private static let dosPattern = try? NSRegularExpression(
        pattern: #"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{2}):(\d{2})(AM|PM)\s+(<DIR>|\d+)\s+(.+)$"#
    )
    static func parse(_ listing: String, basePath: String) throws -> [RemoteFileItem] {
        let lines = listing.split(whereSeparator: \.isNewline).map(String.init)
        return try lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            try parseLine($0, basePath: basePath)
        }
    }

    static func parseLine(_ line: String, basePath: String) throws -> RemoteFileItem {
        if line.contains(";") && line.contains("=") {
            return try parseMLSD(line, basePath: basePath)
        }
        if let item = parseDOS(line, basePath: basePath) { return item }
        if let item = parseUnix(line, basePath: basePath) { return item }
        throw RemoteHubError(
            .unknown,
            message: "The server returned an unsupported directory-listing line.",
            recoverySuggestion: "Enable MLSD on the server or report the sanitized listing format."
        )
    }

    private static func parseMLSD(_ line: String, basePath: String) throws -> RemoteFileItem {
        guard let separator = line.firstIndex(where: \.isWhitespace) else {
            throw parseError()
        }
        let factsPart = line[..<separator]
        let name = line[separator...].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw parseError() }

        var facts: [String: String] = [:]
        for item in factsPart.split(separator: ";") {
            let pair = item.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                facts[pair[0].lowercased()] = String(pair[1])
            }
        }
        let type: RemoteFileItem.ItemType
        switch facts["type"]?.lowercased() {
        case "dir", "cdir", "pdir": type = .directory
        case "os.unix=slink": type = .symbolicLink
        default: type = .file
        }
        return RemoteFileItem(
            name: name,
            path: join(basePath, name),
            type: type,
            size: facts["size"].flatMap(Int64.init),
            permissions: facts["unix.mode"],
            owner: facts["unix.owner"],
            group: facts["unix.group"],
            modifiedAt: facts["modify"].flatMap(parseMLSDDate)
        )
    }

    private static func parseDOS(_ line: String, basePath: String) -> RemoteFileItem? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = dosPattern?.firstMatch(in: line, range: range) else { return nil }
        let values = (1..<match.numberOfRanges).compactMap { index -> String? in
            guard let valueRange = Range(match.range(at: index), in: line) else { return nil }
            return String(line[valueRange])
        }
        guard values.count == 8 else { return nil }
        let marker = values[6]
        let name = values[7]
        let type: RemoteFileItem.ItemType = marker == "<DIR>" ? .directory : .file
        return RemoteFileItem(
            name: name,
            path: join(basePath, name),
            type: type,
            size: type == .file ? Int64(marker) : nil,
            modifiedAt: parseDOSDate(values)
        )
    }

    private static func parseUnix(_ line: String, basePath: String) -> RemoteFileItem? {
        let columns = line.split(maxSplits: 8, whereSeparator: \.isWhitespace)
        guard columns.count == 9 else { return nil }
        let permissions = String(columns[0])
        guard let first = permissions.first, "-dl".contains(first) else { return nil }
        let rawName = String(columns[8])
        let name: String
        let target: String?
        if first == "l", let range = rawName.range(of: " -> ") {
            name = String(rawName[..<range.lowerBound])
            target = String(rawName[range.upperBound...])
        } else {
            name = rawName
            target = nil
        }
        let type: RemoteFileItem.ItemType = first == "d" ? .directory : (first == "l" ? .symbolicLink : .file)
        return RemoteFileItem(
            name: name,
            path: join(basePath, name),
            type: type,
            size: Int64(columns[4]),
            permissions: permissions,
            owner: String(columns[2]),
            group: String(columns[3]),
            modifiedAt: parseUnixDate(month: String(columns[5]), day: String(columns[6]), timeOrYear: String(columns[7])),
            symbolicLinkTarget: target
        )
    }

    private static func join(_ base: String, _ name: String) -> String {
        base == "/" ? "/\(name)" : "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/\(name)"
    }

    private static func parseMLSDDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: String(value.prefix(14)))
    }

    private static func parseDOSDate(_ values: [String]) -> Date? {
        let input = "\(values[0])-\(values[1])-\(values[2]) \(values[3]):\(values[4])\(values[5])"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = values[2].count == 2 ? "MM-dd-yy hh:mma" : "MM-dd-yyyy hh:mma"
        return formatter.date(from: input)
    }

    private static func parseUnixDate(month: String, day: String, timeOrYear: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if timeOrYear.contains(":") {
            let year = Calendar(identifier: .gregorian).component(.year, from: .now)
            formatter.dateFormat = "MMM d yyyy HH:mm"
            return formatter.date(from: "\(month) \(day) \(year) \(timeOrYear)")
        }
        formatter.dateFormat = "MMM d yyyy"
        return formatter.date(from: "\(month) \(day) \(timeOrYear)")
    }

    private static func parseError() -> RemoteHubError {
        RemoteHubError(.unknown, message: "The server returned a malformed MLSD directory entry.")
    }
}
