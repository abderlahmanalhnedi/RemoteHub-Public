import AppKit
import SwiftUI

struct ProtocolBadge: View {
    let kind: ConnectionKind

    var body: some View {
        Label(kind.shortName, systemImage: kind.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(kind.isEncrypted ? Color.accentColor.opacity(0.15) : Color.orange.opacity(0.18))
            .foregroundStyle(kind.isEncrypted ? Color.accentColor : Color.orange)
            .clipShape(Capsule())
            .accessibilityLabel("\(kind.displayName) protocol")
    }
}

struct ErrorBanner: View {
    let error: RemoteHubError
    var dismiss: (() -> Void)?
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(error.message).fontWeight(.semibold)
                    if let recovery = error.recoverySuggestion {
                        Text(recovery).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(showsDetails ? "Hide Details" : "Show Details") {
                    showsDetails.toggle()
                }
                .buttonStyle(.borderless)
                if let dismiss {
                    Button("Dismiss", action: dismiss)
                        .buttonStyle(.borderless)
                }
            }
            if showsDetails {
                Text(error.diagnostics)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error.diagnostics, forType: .string)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

struct ConnectionResultIcon: View {
    let result: ConnectionResult

    var body: some View {
        switch result {
        case .never:
            EmptyView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Last connection succeeded")
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("Last connection failed")
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .help("Last connection was cancelled")
        }
    }
}
