import Foundation

enum RemoteTransferService {
    static func download(
        item: RemoteFileItem,
        to localURL: URL,
        sftp: (any SFTPSession)?,
        ftp: (any FTPClient)?,
        progress: TransferProgressHandler?
    ) async throws {
        if item.type == .directory {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            let children = try await list(path: item.path, sftp: sftp, ftp: ftp)
            for child in children {
                try Task.checkCancellation()
                try await download(
                    item: child,
                    to: localURL.appendingPathComponent(child.name),
                    sftp: sftp,
                    ftp: ftp,
                    progress: progress
                )
            }
        } else if let sftp {
            try await sftp.download(remotePath: item.path, to: localURL, progress: progress)
        } else if let ftp {
            try await ftp.download(remotePath: item.path, to: localURL, progress: progress)
        } else {
            throw RemoteHubError(.networkUnavailable, message: "The remote session is not connected.")
        }
    }

    static func upload(
        localURL: URL,
        to remotePath: String,
        sftp: (any SFTPSession)?,
        ftp: (any FTPClient)?,
        progress: TransferProgressHandler?
    ) async throws {
        let values = try localURL.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            if let sftp {
                try await sftp.createDirectory(path: remotePath)
            } else if let ftp {
                try await ftp.createDirectory(path: remotePath)
            }
            let children = try FileManager.default.contentsOfDirectory(
                at: localURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            for child in children {
                try Task.checkCancellation()
                try await upload(
                    localURL: child,
                    to: join(remotePath, child.lastPathComponent),
                    sftp: sftp,
                    ftp: ftp,
                    progress: progress
                )
            }
        } else if let sftp {
            try await sftp.upload(localURL: localURL, to: remotePath, progress: progress)
        } else if let ftp {
            try await ftp.upload(localURL: localURL, to: remotePath, progress: progress)
        } else {
            throw RemoteHubError(.networkUnavailable, message: "The remote session is not connected.")
        }
    }

    static func uniqueRemotePath(
        basePath: String,
        name: String,
        existingNames: Set<String>
    ) -> String {
        guard existingNames.contains(name.lowercased()) else { return join(basePath, name) }
        let extensionValue = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidate = extensionValue.isEmpty
                ? "\(stem) \(index)"
                : "\(stem) \(index).\(extensionValue)"
            if !existingNames.contains(candidate.lowercased()) {
                return join(basePath, candidate)
            }
            index += 1
        }
    }

    static func join(_ base: String, _ name: String) -> String {
        if base == "/" { return "/\(name)" }
        return "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/\(name)"
    }

    private static func list(
        path: String,
        sftp: (any SFTPSession)?,
        ftp: (any FTPClient)?
    ) async throws -> [RemoteFileItem] {
        if let sftp { return try await sftp.list(path: path) }
        if let ftp { return try await ftp.list(path: path) }
        throw RemoteHubError(.networkUnavailable, message: "The remote session is not connected.")
    }
}
