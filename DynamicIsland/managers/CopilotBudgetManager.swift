/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import Defaults
import Combine

@MainActor
final class CopilotBudgetManager: ObservableObject {
    static let shared = CopilotBudgetManager()

    @Published private(set) var premiumUsed: Int = 0
    @Published private(set) var premiumRemaining: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    private var timer: Timer?

    var total: Int { premiumUsed + premiumRemaining }
    var usageFraction: Double {
        guard total > 0 else { return 0 }
        return Double(premiumUsed) / Double(total)
    }

    private init() {
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        guard Defaults[.enableLockScreenCopilotBudgetWidget] else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "http://127.0.0.1:3082/budget") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(CopilotBudgetResponse.self, from: data)
            premiumUsed = json.premium
            premiumRemaining = json.remaining
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private struct CopilotBudgetResponse: Decodable {
    let premium: Int
    let remaining: Int
}
