import Foundation

struct CursorQuotaLimits {
    let cursorModels: UsageLimit?
    let otherModels: UsageLimit?

    var isEmpty: Bool {
        cursorModels == nil && otherModels == nil
    }
}

// Fetches Cursor's current billing-period usage via the local session token.
struct CursorQuotaClient {
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    // Never throws: any credential/network/parse failure yields (nil, nil). Cursor has no 5h session window.
    func fetchLimits() async -> CursorQuotaLimits {
        if let token = CursorTokenStore.accessToken(),
           let payload = await fetchCurrentPeriod(token: token) {
            return usageLimits(from: payload)
        }
        if let cookie = CursorTokenStore.sessionCookie(),
           let payload = await fetchUsageSummary(cookieToken: cookie.cookieToken) {
            return usageLimits(from: payload)
        }
        return CursorQuotaLimits(cursorModels: nil, otherModels: nil)
    }

    private func fetchCurrentPeriod(token: String) async -> CursorQuotaPayload? {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15
        return await fetchPayload(request)
    }

    private func fetchUsageSummary(cookieToken: String) async -> CursorQuotaPayload? {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.setValue("WorkosCursorSessionToken=\(cookieToken)", forHTTPHeaderField: "Cookie")
        request.timeoutInterval = 15
        return await fetchPayload(request)
    }

    private func fetchPayload(_ request: URLRequest) async -> CursorQuotaPayload? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                return nil
            }
            return try CursorQuotaPayload.decode(data)
        } catch {
            return nil
        }
    }

    private func usageLimits(from payload: CursorQuotaPayload) -> CursorQuotaLimits {
        let cursorModels = payload.cursorModelsUsedPercent.map {
            UsageLimit(used: displayPercent($0), limit: 100, resetsAt: payload.resetsAt)
        }
        let otherModels = payload.otherModelsUsedPercent.map {
            UsageLimit(used: displayPercent($0), limit: 100, resetsAt: payload.resetsAt)
        }
        if cursorModels == nil, otherModels == nil, let combined = payload.combinedUsedPercent {
            return CursorQuotaLimits(
                cursorModels: nil,
                otherModels: UsageLimit(used: combined, limit: 100, resetsAt: payload.resetsAt)
            )
        }
        return CursorQuotaLimits(cursorModels: cursorModels, otherModels: otherModels)
    }

    private func displayPercent(_ percent: Double) -> Double {
        percent > 0 && percent < 1 ? 1 : percent
    }
}
