import Foundation

struct RDPLaunchSpecification: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let standardInput: Data?
}

enum RDPArgumentBuilder {
    static func build(
        installation: RDPInstallation,
        configuration: RDPConnectionConfiguration,
        password: String?,
        allowPrompt: Bool = false
    ) throws -> RDPLaunchSpecification {
        var arguments = [
            "/v:\(formattedHost(configuration.host, port: configuration.port))",
            "/u:\(configuration.username)"
        ]

        if let domain = configuration.domain, !domain.isEmpty {
            arguments.append("/d:\(domain)")
        }
        let settings = configuration.settings
        switch settings.displayMode {
        case .fullScreen:
            arguments.append("/f")
        case .windowed:
            if settings.dynamicResolution {
                arguments.append("/dynamic-resolution")
            } else {
                arguments += ["/w:\(settings.width)", "/h:\(settings.height)"]
            }
        }
        if settings.multiMonitor { arguments.append("/multimon") }
        arguments.append(settings.clipboard ? "+clipboard" : "-clipboard")
        if settings.audio { arguments.append("/sound") }
        if settings.microphone { arguments.append("/microphone") }
        if settings.adminSession { arguments.append("/admin") }
        arguments.append("/network:\(networkArgument(settings.networkProfile))")

        switch settings.certificatePolicy {
        case .prompt:
            break
        case .trustOnFirstUse:
            arguments.append("/cert:tofu")
        case .ignore:
            arguments.append("/cert:ignore")
        }

        var input: Data?
        if let password {
            if installation.supportsSafePasswordInput {
                arguments.append("/from-stdin:force")
                input = Data("\(password)\n".utf8)
            } else if !allowPrompt {
                throw RemoteHubError(
                    .incompatibleFreeRDP,
                    message: "This FreeRDP client cannot receive a password safely.",
                    recoverySuggestion: "Use the bundled client or a compatible SDL FreeRDP build."
                )
            }
        }

        if settings.redirectDrive {
            guard let bookmark = settings.redirectedFolderBookmark,
                  let path = String(data: bookmark, encoding: .utf8),
                  !path.isEmpty
            else {
                throw RemoteHubError(
                    .validation,
                    message: "Select a local folder before enabling drive redirection."
                )
            }
            arguments.append("/drive:RemoteHub,\(path)")
        }

        return RDPLaunchSpecification(
            executableURL: installation.executableURL,
            arguments: arguments,
            standardInput: input
        )
    }

    private static func formattedHost(_ host: String, port: Int) -> String {
        host.contains(":") && !(host.hasPrefix("[") && host.hasSuffix("]"))
            ? "[\(host)]:\(port)"
            : "\(host):\(port)"
    }

    private static func networkArgument(_ profile: RDPNetworkProfile) -> String {
        switch profile {
        case .autoDetect: "auto"
        case .modem: "modem"
        case .broadbandLow: "broadband-low"
        case .broadbandHigh: "broadband-high"
        case .wan: "wan"
        case .lan: "lan"
        }
    }
}
