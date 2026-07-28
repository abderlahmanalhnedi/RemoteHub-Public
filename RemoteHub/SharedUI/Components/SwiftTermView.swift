import AppKit
import SwiftTerm
import SwiftUI

struct SwiftTermSessionView: NSViewRepresentable {
    let session: any SSHSession
    let fontName: String
    let fontSize: Double
    var onTitleChange: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onTitleChange: onTitleChange)
    }

    func makeNSView(context: Context) -> TerminalView {
        let font = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let view = TerminalView(frame: .zero, font: font)
        view.terminalDelegate = context.coordinator
        view.setAccessibilityLabel("SSH terminal")
        context.coordinator.startFeeding(view)
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {
        let font = NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if view.font.fontName != font.fontName || view.font.pointSize != font.pointSize {
            view.font = font
        }
    }

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.stop()
        view.terminalDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor TerminalViewDelegate {
        private let session: any SSHSession
        private let onTitleChange: @MainActor (String) -> Void
        private var feedTask: Task<Void, Never>?

        init(session: any SSHSession, onTitleChange: @escaping @MainActor (String) -> Void) {
            self.session = session
            self.onTitleChange = onTitleChange
        }

        func startFeeding(_ view: TerminalView) {
            feedTask = Task { @MainActor [weak view, session] in
                do {
                    for try await data in session.output {
                        try Task.checkCancellation()
                        view?.feed(byteArray: Array(data)[...])
                    }
                } catch {
                    let message = "\r\n[RemoteHub: \(Redactor.sanitize(error.localizedDescription))]\r\n"
                    view?.feed(text: message)
                }
            }
        }

        func stop() {
            feedTask?.cancel()
            feedTask = nil
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task {
                do {
                    try await session.resize(columns: newCols, rows: newRows)
                } catch {
                    show(error, in: source)
                }
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            Task { @MainActor in onTitleChange(title) }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            Task {
                do {
                    try await session.send(Data(data))
                } catch {
                    show(error, in: source)
                }
            }
        }

        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        private func show(_ error: Error, in view: TerminalView) {
            let message = "\r\n[RemoteHub: \(Redactor.sanitize(error.localizedDescription))]\r\n"
            view.feed(text: message)
        }
    }
}
