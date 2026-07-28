import Foundation
import Observation

enum TransferStatus: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

struct TransferRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let key: String
    let title: String
    var status: TransferStatus
    var progress: TransferProgress
    var errorMessage: String?
    var attempt: Int
}

@MainActor
@Observable
final class TransferQueue {
    typealias Operation = @Sendable (TransferProgressHandler?) async throws -> Void

    private(set) var records: [TransferRecord] = []
    var maximumConcurrent: Int {
        didSet {
            maximumConcurrent = min(8, max(1, maximumConcurrent))
            schedule()
        }
    }

    private var operations: [UUID: Operation] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(maximumConcurrent: Int = AppConstants.defaultTransferConcurrency) {
        self.maximumConcurrent = min(8, max(1, maximumConcurrent))
    }

    @discardableResult
    func enqueue(key: String, title: String, operation: @escaping Operation) -> UUID? {
        let activeStatuses: Set<TransferStatus> = [.queued, .running]
        guard !records.contains(where: { $0.key == key && activeStatuses.contains($0.status) }) else {
            return nil
        }
        let id = UUID()
        records.append(TransferRecord(
            id: id,
            key: key,
            title: title,
            status: .queued,
            progress: TransferProgress(bytesTransferred: 0, totalBytes: nil, bytesPerSecond: 0),
            errorMessage: nil,
            attempt: 1
        ))
        operations[id] = operation
        AppLog.transfers.info("Transfer queued")
        schedule()
        return id
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        update(id) {
            $0.status = .cancelled
            $0.errorMessage = nil
        }
        schedule()
    }

    func retry(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }),
              record.status == .failed || record.status == .cancelled,
              operations[id] != nil
        else { return }
        update(id) {
            $0.status = .queued
            $0.errorMessage = nil
            $0.attempt += 1
            $0.progress = TransferProgress(bytesTransferred: 0, totalBytes: nil, bytesPerSecond: 0)
        }
        schedule()
    }

    func clearFinished() {
        let finished: Set<TransferStatus> = [.succeeded, .failed, .cancelled]
        let ids = Set(records.filter { finished.contains($0.status) }.map(\.id))
        records.removeAll { ids.contains($0.id) }
        for id in ids {
            operations.removeValue(forKey: id)
            tasks.removeValue(forKey: id)
        }
    }

    private func schedule() {
        while tasks.count < maximumConcurrent,
              let record = records.first(where: { $0.status == .queued }),
              let operation = operations[record.id] {
            update(record.id) { $0.status = .running }
            let id = record.id
            tasks[id] = Task { [queue = self] in
                do {
                    try await operation { progress in
                        Task { @MainActor in
                            queue.update(id) { $0.progress = progress }
                        }
                    }
                    guard !Task.isCancelled else {
                        queue.finish(id, status: .cancelled, error: nil)
                        return
                    }
                    queue.finish(id, status: .succeeded, error: nil)
                } catch is CancellationError {
                    queue.finish(id, status: .cancelled, error: nil)
                } catch {
                    queue.finish(id, status: .failed, error: Redactor.sanitize(error.localizedDescription))
                }
            }
        }
    }

    private func finish(_ id: UUID, status: TransferStatus, error: String?) {
        tasks.removeValue(forKey: id)
        update(id) {
            $0.status = status
            $0.errorMessage = error
        }
        AppLog.transfers.info("Transfer finished with status \(status.rawValue, privacy: .public)")
        schedule()
    }

    private func update(_ id: UUID, mutation: (inout TransferRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        mutation(&records[index])
    }
}
