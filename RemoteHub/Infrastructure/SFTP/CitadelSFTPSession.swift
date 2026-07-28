import Citadel
import Foundation
import NIO

actor CitadelSFTPSession: SFTPSession {
    private let client: SFTPClient

    init(client: SFTPClient) {
        self.client = client
    }

    func list(path: String) async throws -> [RemoteFileItem] {
        let names = try await client.listDirectory(atPath: path)
        return names.flatMap(\.components).compactMap { component in
            guard component.filename != ".", component.filename != ".." else { return nil }
            let attributes = component.attributes
            let permissions = attributes.permissions
            let type = itemType(permissions: permissions)
            let joinedPath = path == "/" ? "/\(component.filename)" : "\(path)/\(component.filename)"
            return RemoteFileItem(
                name: component.filename,
                path: joinedPath,
                type: type,
                size: attributes.size.map(Int64.init),
                permissions: permissions.map { String(format: "%04o", $0 & 0o7777) },
                owner: attributes.uidgid.map { String($0.userId) },
                group: attributes.uidgid.map { String($0.groupId) },
                modifiedAt: attributes.accessModificationTime?.modificationTime
            )
        }
    }

    func createDirectory(path: String) async throws {
        try await client.createDirectory(atPath: path)
    }

    func rename(from: String, to: String) async throws {
        try await client.rename(at: from, to: to)
    }

    func removeFile(path: String) async throws {
        try await client.remove(at: path)
    }

    func removeDirectory(path: String) async throws {
        try await client.rmdir(at: path)
    }

    func download(
        remotePath: String,
        to localURL: URL,
        progress: TransferProgressHandler?
    ) async throws {
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let local = try FileHandle(forWritingTo: localURL)
        defer { try? local.close() }
        try await client.withFile(filePath: remotePath, flags: .read) { file in
            let attributes = try await file.readAttributes()
            let total = attributes.size.map(Int64.init)
            var offset: UInt64 = 0
            let clock = ContinuousClock()
            let started = clock.now
            while true {
                try Task.checkCancellation()
                let buffer = try await file.read(from: offset, length: 256 * 1024)
                guard buffer.readableBytes > 0 else { break }
                let data = Data(buffer.readableBytesView)
                try local.write(contentsOf: data)
                offset += UInt64(data.count)
                let duration = started.duration(to: clock.now)
                progress?(TransferProgress(
                    bytesTransferred: Int64(offset),
                    totalBytes: total,
                    bytesPerSecond: Self.rate(bytes: Int64(offset), duration: duration)
                ))
            }
        }
    }

    func upload(
        localURL: URL,
        to remotePath: String,
        progress: TransferProgressHandler?
    ) async throws {
        let local = try FileHandle(forReadingFrom: localURL)
        defer { try? local.close() }
        let total = (try? local.seekToEnd()).map(Int64.init)
        try local.seek(toOffset: 0)
        try await client.withFile(
            filePath: remotePath,
            flags: [.write, .create, .truncate]
        ) { file in
            var offset: UInt64 = 0
            let clock = ContinuousClock()
            let started = clock.now
            while let data = try local.read(upToCount: 256 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset += UInt64(data.count)
                let duration = started.duration(to: clock.now)
                progress?(TransferProgress(
                    bytesTransferred: Int64(offset),
                    totalBytes: total,
                    bytesPerSecond: Self.rate(bytes: Int64(offset), duration: duration)
                ))
            }
        }
    }

    func setPermissions(path: String, mode: UInt32) async throws {
        var attributes = SFTPFileAttributes.none
        attributes.permissions = mode
        try await client.setAttributes(at: path, to: attributes)
    }

    func disconnect() async {
        try? await client.close()
    }

    private func itemType(permissions: UInt32?) -> RemoteFileItem.ItemType {
        guard let mode = permissions else { return .file }
        switch mode & 0o170000 {
        case 0o040000: return .directory
        case 0o120000: return .symbolicLink
        default: return .file
        }
    }

    nonisolated private static func rate(bytes: Int64, duration: Duration) -> Double {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        return seconds > 0 ? Double(bytes) / seconds : 0
    }
}
