import SwiftUI

struct TransferQueueView: View {
    @Environment(AppContainer.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfers").font(.headline)
                Spacer()
                Button("Clear Finished") { app.transfers.clearFinished() }
                    .disabled(app.transfers.records.isEmpty)
            }
            .padding()
            Divider()
            if app.transfers.records.isEmpty {
                ContentUnavailableView(
                    "No transfers",
                    systemImage: "arrow.up.arrow.down",
                    description: Text("Uploads and downloads appear here.")
                )
            } else {
                List(app.transfers.records) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: icon(record.status))
                            Text(record.title).lineLimit(1)
                            Spacer()
                            Text(record.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if record.status == .running {
                            if let total = record.progress.totalBytes, total > 0 {
                                ProgressView(value: Double(record.progress.bytesTransferred), total: Double(total))
                            } else {
                                ProgressView()
                            }
                            Text(progressText(record.progress))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let error = record.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        HStack {
                            Spacer()
                            if record.status == .queued || record.status == .running {
                                Button("Cancel") { app.transfers.cancel(record.id) }
                            } else if record.status == .failed || record.status == .cancelled {
                                Button("Retry") { app.transfers.retry(record.id) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func icon(_ status: TransferStatus) -> String {
        switch status {
        case .queued: "clock"
        case .running: "arrow.up.arrow.down.circle"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "minus.circle"
        }
    }

    private func progressText(_ progress: TransferProgress) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: progress.bytesTransferred, countStyle: .file)
        let speed = ByteCountFormatter.string(fromByteCount: Int64(progress.bytesPerSecond), countStyle: .file)
        return "\(bytes) • \(speed)/s"
    }
}
