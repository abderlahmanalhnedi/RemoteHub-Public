import Foundation

struct ProcessRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let standardInput: Data?
}

struct ProcessResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
}

struct FoundationProcessRunner: ProcessRunning {
    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = request.executableURL
            process.arguments = request.arguments
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ProcessResult(
                    terminationStatus: process.terminationStatus,
                    standardOutput: output,
                    standardError: error
                ))
            }
            do {
                try process.run()
                if let data = request.standardInput {
                    inputPipe.fileHandleForWriting.write(data)
                }
                try? inputPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: RemoteHubError(
                    .processLaunchFailed,
                    message: "A required helper process could not be launched.",
                    recoverySuggestion: "Verify the executable path and permissions.",
                    technicalDetails: error.localizedDescription
                ))
            }
        }
    }
}
