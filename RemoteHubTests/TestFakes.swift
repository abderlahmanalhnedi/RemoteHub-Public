import Foundation
@testable import RemoteHub

actor FakeSSHTransport: SSHTransport {
    let session: FakeSSHSession
    private(set) var configurations: [SSHConnectionConfiguration] = []

    init(session: FakeSSHSession = FakeSSHSession()) {
        self.session = session
    }

    func connect(configuration: SSHConnectionConfiguration) async throws -> any SSHSession {
        configurations.append(configuration)
        return session
    }
}

actor FakeSSHSession: SSHSession {
    nonisolated let output: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private(set) var sent: [Data] = []
    private(set) var sizes: [(Int, Int)] = []
    private(set) var disconnected = false
    let sftp = FakeSFTPSession()

    init() {
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        output = pair.stream
        continuation = pair.continuation
    }

    func emit(_ data: Data) {
        continuation.yield(data)
    }

    func send(_ data: Data) async throws {
        sent.append(data)
    }

    func resize(columns: Int, rows: Int) async throws {
        sizes.append((columns, rows))
    }

    func openSFTP() async throws -> any SFTPSession {
        sftp
    }

    func disconnect() async {
        disconnected = true
        continuation.finish()
    }
}

actor FakeSFTPSession: SFTPSession {
    var items: [RemoteFileItem] = []
    private(set) var operations: [String] = []

    func list(path: String) async throws -> [RemoteFileItem] {
        operations.append("list:\(path)")
        return items
    }

    func createDirectory(path: String) async throws { operations.append("mkdir:\(path)") }
    func rename(from: String, to: String) async throws { operations.append("rename:\(from):\(to)") }
    func removeFile(path: String) async throws { operations.append("rm:\(path)") }
    func removeDirectory(path: String) async throws { operations.append("rmdir:\(path)") }

    func download(
        remotePath: String,
        to localURL: URL,
        progress: TransferProgressHandler?
    ) async throws {
        operations.append("download:\(remotePath)")
        progress?(TransferProgress(bytesTransferred: 10, totalBytes: 10, bytesPerSecond: 10))
    }

    func upload(
        localURL: URL,
        to remotePath: String,
        progress: TransferProgressHandler?
    ) async throws {
        operations.append("upload:\(remotePath)")
        progress?(TransferProgress(bytesTransferred: 10, totalBytes: 10, bytesPerSecond: 10))
    }

    func setPermissions(path: String, mode: UInt32) async throws {
        operations.append("chmod:\(path):\(mode)")
    }

    func disconnect() async { operations.append("disconnect") }
}

actor FakeFTPClient: FTPClient {
    private(set) var arguments: [String] = []

    func connect(configuration: FTPConnectionConfiguration) async throws {
        arguments.append("connect:\(configuration.host)")
    }

    func list(path: String) async throws -> [RemoteFileItem] {
        arguments.append("list:\(path)")
        return []
    }

    func createDirectory(path: String) async throws { arguments.append("mkdir:\(path)") }
    func rename(from: String, to: String) async throws { arguments.append("rename:\(from):\(to)") }
    func removeFile(path: String) async throws { arguments.append("remove:\(path)") }
    func removeDirectory(path: String) async throws { arguments.append("rmdir:\(path)") }
    func upload(localURL: URL, to remotePath: String, progress: TransferProgressHandler?) async throws {
        arguments.append("upload:\(remotePath)")
    }
    func download(remotePath: String, to localURL: URL, progress: TransferProgressHandler?) async throws {
        arguments.append("download:\(remotePath)")
    }
    func disconnect() async { arguments.append("disconnect") }
}

struct FakeFilePickerBookmarkProvider: Sendable {
    func bookmark(for url: URL) -> Data { Data(url.path.utf8) }
    func resolve(_ data: Data) -> URL? {
        String(data: data, encoding: .utf8).map { URL(fileURLWithPath: $0) }
    }
}

struct FixedClock: Sendable {
    let now: Date
}
