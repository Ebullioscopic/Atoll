import Foundation

/// Foundation-only transport, independently testable without the app/test host.
struct CopilotQuotaClient {
    let fetch: (URLRequest) async throws -> (Data, URLResponse)

    init(session: URLSession? = nil,
         fetch: ((URLRequest) async throws -> (Data, URLResponse))? = nil) {
        // A redirect must not move the account request to a different host.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        let session = session ?? URLSession(configuration: configuration, delegate: CopilotRedirectPolicy(), delegateQueue: nil)
        self.fetch = fetch ?? { try await session.data(for: $0) }
    }

    func fetchQuota(host: String, token: String?) async throws -> CopilotQuotaPayload {
        let url = try CopilotEndpoint.url(host: host)
        guard let token, CopilotTokenValidation.isValid(token) else {
            throw CopilotQuotaError.notConfigured
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2025-05-01", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Atoll-Copilot-Usage", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        let data: Data
        let response: URLResponse
        do { (data, response) = try await fetch(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw CopilotQuotaError.networkUnavailable }
        guard let http = response as? HTTPURLResponse else { throw CopilotQuotaError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw CopilotQuotaError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw CopilotQuotaError.unavailable(http.statusCode) }
        guard response.url == url, data.count <= 1_048_576 else {
            throw CopilotQuotaError.invalidResponse
        }
        let payload: CopilotQuotaPayload
        do { payload = try JSONDecoder().decode(CopilotQuotaPayload.self, from: data) }
        catch { throw CopilotQuotaError.invalidResponse }
        guard !payload.quotas.isEmpty else { throw CopilotQuotaError.invalidResponse }
        return payload
    }
}

final class CopilotRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
