import Foundation

enum RDPErrorMapper {
    static func map(
        _ termination: RDPProcessTermination,
        username: String?,
        password: String? = nil
    ) -> RemoteHubError? {
        if termination.wasUserInitiated || (
            termination.reason == .exited && termination.exitCode == 0
        ) {
            return nil
        }

        let diagnostics = sanitizedDiagnostics(
            termination,
            username: username,
            password: password
        )
        let lower = diagnostics.lowercased()

        if matches(lower, [
            "errconnect_dns_error",
            "errconnect_dns_name_not_found",
            "name or service not known",
            "nodename nor servname provided",
            "temporary failure in name resolution",
            "getaddrinfo failed"
        ]) {
            return RemoteHubError(
                .dns,
                message: "The RDP host name could not be resolved.",
                recoverySuggestion: "Check the host name and DNS or VPN connection, then reconnect.",
                technicalDetails: diagnostics
            )
        }
        if matches(lower, [
            "connection timed out",
            "operation timed out",
            "errconnect_connect_transport_failed",
            "transport connect timeout"
        ]) {
            return RemoteHubError(
                .timeout,
                message: "The RDP connection timed out.",
                recoverySuggestion: "Check the server, network, VPN, and firewall, then reconnect.",
                technicalDetails: diagnostics
            )
        }
        if matches(lower, [
            "connection refused",
            "actively refused",
            "econnrefused"
        ]) {
            return RemoteHubError(
                .connectionRefused,
                message: "The RDP server refused the connection.",
                recoverySuggestion: "Verify that Remote Desktop is enabled and listening on the configured port.",
                technicalDetails: diagnostics
            )
        }
        if matches(lower, [
            "errconnect_nla_failed",
            "nla_client_authenticate failure",
            "nla_recv_pdu() fail",
            "nla begin failed",
            "credssp",
            "network level authentication"
        ]) {
            return RemoteHubError(
                .networkLevelAuthenticationFailed,
                message: "Network Level Authentication failed.",
                recoverySuggestion: "Verify the account, domain, server NLA policy, and system clock, then reconnect.",
                technicalDetails: diagnostics
            )
        }
        if matches(lower, [
            "errconnect_authentication_failed",
            "errconnect_logon_failure",
            "status_logon_failure",
            "logon failure",
            "authentication failure",
            "the credentials supplied"
        ]) {
            return RemoteHubError(
                .authenticationFailed,
                message: "The RDP server rejected the credentials.",
                recoverySuggestion: "Verify the username, password, and domain, then reconnect.",
                technicalDetails: diagnostics
            )
        }
        if matches(lower, [
            "certificate verify failed",
            "certificate verification failure",
            "errconnect_tls_connect_failed",
            "certificate name mismatch",
            "untrusted certificate"
        ]) {
            return RemoteHubError(
                .certificateError,
                message: "The RDP server certificate could not be verified.",
                recoverySuggestion: "Review the server identity and certificate policy before reconnecting.",
                technicalDetails: diagnostics
            )
        }
        if termination.reason == .uncaughtSignal {
            return RemoteHubError(
                .externalClientCrash,
                message: "The Remote Desktop client crashed.",
                recoverySuggestion: "Copy diagnostics and reconnect. If it repeats, report the crash to RemoteHub support.",
                technicalDetails: diagnostics
            )
        }
        return RemoteHubError(
            .externalClientCrash,
            message: "The Remote Desktop client exited unexpectedly.",
            recoverySuggestion: "Copy diagnostics, verify the profile, and reconnect.",
            technicalDetails: diagnostics
        )
    }

    static func sanitizedDiagnostics(
        _ termination: RDPProcessTermination,
        username: String?,
        password: String? = nil
    ) -> String {
        let output = String(decoding: termination.standardOutput, as: UTF8.self)
        let error = String(decoding: termination.standardError, as: UTF8.self)
        let combined = """
        FreeRDP termination reason: \(termination.reason)
        FreeRDP exit code: \(termination.exitCode)
        stdout:
        \(output)
        stderr:
        \(error)
        """
        return Redactor.sanitize(
            combined,
            sensitiveValues: [username, password].compactMap { $0?.isEmpty == false ? $0 : nil }
        )
    }

    private static func matches(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }
}
