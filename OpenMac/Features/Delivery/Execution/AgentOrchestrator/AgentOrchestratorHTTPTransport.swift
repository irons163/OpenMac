import Foundation

nonisolated struct AgentOrchestratorHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]

    nonisolated init(
        data: Data,
        statusCode: Int,
        headers: [String: String] = [:]
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

nonisolated protocol AgentOrchestratorHTTPTransport: Sendable {
    func send(
        _ request: URLRequest
    ) async throws -> AgentOrchestratorHTTPResponse
}

nonisolated struct URLSessionAgentOrchestratorHTTPTransport:
    AgentOrchestratorHTTPTransport
{
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func send(
        _ request: URLRequest
    ) async throws -> AgentOrchestratorHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let headers = httpResponse.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, item in
            guard let key = item.key as? String else { return }
            result[key.lowercased()] = String(describing: item.value)
        }
        return AgentOrchestratorHTTPResponse(
            data: data,
            statusCode: httpResponse.statusCode,
            headers: headers
        )
    }
}
