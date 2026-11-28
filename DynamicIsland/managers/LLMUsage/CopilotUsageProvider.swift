import Foundation
import Defaults

struct CopilotUsageProvider: UsageProvider {
    let id: ProviderID = .copilot
    let quotaClient: CopilotQuotaClient
    let credentials: () -> (host: String, token: String?)

    init(session: URLSession? = nil,
         fetch: ((URLRequest) async throws -> (Data, URLResponse))? = nil,
         credentials: @escaping () -> (host: String, token: String?) = {
             let host = Defaults[.copilotHost]
             return (host, CopilotTokenStore.read(host: host))
         }) {
        self.quotaClient = CopilotQuotaClient(session: session, fetch: fetch)
        self.credentials = credentials
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let (host, token) = credentials()
        let payload = try await quotaClient.fetchQuota(host: host, token: token)
        var snapshot = UsageSnapshot()
        snapshot.copilotQuotas = payload.quotas
        snapshot.plan = payload.copilot_plan
        snapshot.lastUpdated = now
        return snapshot
    }
}
