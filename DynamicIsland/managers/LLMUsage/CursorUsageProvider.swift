import Foundation

struct CursorUsageProvider: UsageProvider {
    let id: ProviderID = .cursor
    let quotaClient: CursorQuotaClient

    init(session: URLSession = URLSession(configuration: .ephemeral), quotaClient: CursorQuotaClient? = nil) {
        self.quotaClient = quotaClient ?? CursorQuotaClient(session: session)
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let quota = await quotaClient.fetchLimits()
        guard !quota.isEmpty else {
            throw UsageError.notConfigured("Cursor quota unavailable")
        }

        var snapshot = UsageSnapshot()
        snapshot.sessionLimit = quota.cursorModels
        snapshot.weekLimit = quota.otherModels
        snapshot.lastUpdated = now
        return snapshot
    }
}
