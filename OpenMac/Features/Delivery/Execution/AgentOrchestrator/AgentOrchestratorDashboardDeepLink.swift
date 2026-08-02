import Foundation

nonisolated enum AgentOrchestratorDashboardRouteStyle: String, Codable, Equatable, Sendable {
    /// The current AO web renderer uses TanStack Router hash history so it can
    /// also run from the packaged Electron renderer.
    case hash
    /// Reserved for a future AO web server that serves routes directly.
    case path
}

nonisolated enum AgentOrchestratorDashboardDeepLinkError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidBaseURL(URL)
    case nonLoopbackBaseURL(URL)
    case invalidIdentifier(String)
    case noProject
    case unavailable(URL, Int)
    case unexpectedContentType(URL, String?)
    case emptyResponse(URL)

    nonisolated var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(url):
            return "The AO dashboard URL must be an http(s) root URL: "
                + url.absoluteString
        case let .nonLoopbackBaseURL(url):
            return "The AO dashboard must use a loopback URL, not "
                + url.absoluteString + "."
        case let .invalidIdentifier(identifier):
            return "The AO dashboard route identifier is unsafe: "
                + identifier + "."
        case .noProject:
            return "Connect to AO and discover at least one project before verifying its dashboard."
        case let .unavailable(url, statusCode):
            return "The AO dashboard route was not available at "
                + url.absoluteString + " (HTTP " + String(statusCode) + ")."
        case let .unexpectedContentType(url, contentType):
            return "The AO dashboard route at " + url.absoluteString
                + " did not return HTML (Content-Type: "
                + (contentType ?? "missing") + ")."
        case let .emptyResponse(url):
            return "The AO dashboard route at " + url.absoluteString
                + " returned an empty document."
        }
    }
}

/// A deliberately small, loopback-only description of the AO browser route.
/// The daemon URL and the dashboard URL are separate: the installed AO desktop
/// currently exposes the former only, while a web renderer may expose the
/// latter on another local port.
nonisolated struct AgentOrchestratorDashboardConfiguration:
    Equatable,
    Sendable
{
    static let defaultsKey = "delivery.agentOrchestrator.dashboardBaseURL"

    let baseURL: URL
    let routeStyle: AgentOrchestratorDashboardRouteStyle

    nonisolated init(
        baseURL: URL,
        routeStyle: AgentOrchestratorDashboardRouteStyle = .hash
    ) throws {
        guard let components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ),
        let scheme = components.scheme?.lowercased(),
        scheme == "http" || scheme == "https",
        components.user == nil,
        components.password == nil,
        components.query == nil,
        components.fragment == nil,
        components.path.isEmpty || components.path == "/" else {
            throw AgentOrchestratorDashboardDeepLinkError.invalidBaseURL(baseURL)
        }

        let host = components.host?.lowercased() ?? ""
        guard host == "localhost"
                || host == "127.0.0.1"
                || host == "::1" else {
            throw AgentOrchestratorDashboardDeepLinkError
                .nonLoopbackBaseURL(baseURL)
        }

        var normalizedComponents = components
        normalizedComponents.path = "/"
        normalizedComponents.fragment = nil
        guard let normalizedURL = normalizedComponents.url else {
            throw AgentOrchestratorDashboardDeepLinkError.invalidBaseURL(baseURL)
        }

        self.baseURL = normalizedURL
        self.routeStyle = routeStyle
    }

    nonisolated func projectURL(projectID: String) throws -> URL {
        try routeURL(projectID: projectID, sessionID: nil)
    }

    nonisolated func sessionURL(
        projectID: String,
        sessionID: String
    ) throws -> URL {
        try routeURL(projectID: projectID, sessionID: sessionID)
    }

    nonisolated private func routeURL(
        projectID: String,
        sessionID: String?
    ) throws -> URL {
        let encodedProjectID = try Self.safePathComponent(projectID)
        let encodedSessionID: String?
        if let sessionID {
            encodedSessionID = try Self.safePathComponent(sessionID)
        } else {
            encodedSessionID = nil
        }

        let route = encodedSessionID.map {
            "/projects/\(encodedProjectID)/sessions/\($0)"
        } ?? "/projects/\(encodedProjectID)"

        switch routeStyle {
        case .hash:
            guard var components = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: false
            ) else {
                throw AgentOrchestratorDashboardDeepLinkError.invalidBaseURL(baseURL)
            }
            components.fragment = route
            guard let url = components.url else {
                throw AgentOrchestratorDashboardDeepLinkError.invalidBaseURL(baseURL)
            }
            return url
        case .path:
            var components = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: false
            )
            components?.path = route
            guard let url = components?.url else {
                throw AgentOrchestratorDashboardDeepLinkError.invalidBaseURL(baseURL)
            }
            return url
        }
    }

    nonisolated private static func safePathComponent(
        _ rawValue: String
    ) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_."))
        guard !value.isEmpty,
              value == rawValue,
              value != ".",
              value != "..",
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains("%"),
              value.unicodeScalars.allSatisfy(allowed.contains) else {
            throw AgentOrchestratorDashboardDeepLinkError
                .invalidIdentifier(rawValue)
        }
        return value
    }
}

nonisolated struct AgentOrchestratorDashboardRouteVerifier: Sendable {
    private let transport: any AgentOrchestratorHTTPTransport

    nonisolated init(
        transport: any AgentOrchestratorHTTPTransport =
            URLSessionAgentOrchestratorHTTPTransport()
    ) {
        self.transport = transport
    }

    /// Verifies the exact URL before OpenMac asks the system browser to open it.
    /// Hash routes are client-side, so the probe intentionally requires the
    /// dashboard document (HTML) rather than the AO daemon's JSON response.
    nonisolated func verify(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 5
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let response = try await transport.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw AgentOrchestratorDashboardDeepLinkError
                .unavailable(url, response.statusCode)
        }

        let contentType = response.headers.first { key, _ in
            key.caseInsensitiveCompare("content-type") == .orderedSame
        }?.value
        guard let contentType,
              contentType.lowercased().contains("text/html") else {
            throw AgentOrchestratorDashboardDeepLinkError
                .unexpectedContentType(url, contentType)
        }
        guard !response.data.isEmpty else {
            throw AgentOrchestratorDashboardDeepLinkError.emptyResponse(url)
        }
        return url
    }

    nonisolated func verify(
        configuration: AgentOrchestratorDashboardConfiguration,
        projectID: String,
        sessionID: String? = nil
    ) async throws -> URL {
        let url: URL
        if let sessionID {
            url = try configuration.sessionURL(
                projectID: projectID,
                sessionID: sessionID
            )
        } else {
            url = try configuration.projectURL(projectID: projectID)
        }
        return try await verify(url)
    }
}
