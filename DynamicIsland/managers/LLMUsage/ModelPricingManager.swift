/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import SwiftUI
import Defaults

/// Model for dynamic pricing data structure
struct ModelPricingData: Codable {
    let models: [ModelPriceEntry]
    let lastUpdated: String?
    
    enum CodingKeys: String, CodingKey {
        case models
        case lastUpdated = "last_updated"
    }
}

struct ModelPriceEntry: Codable, Identifiable {
    let id: String
    let name: String
    let pricing: ModelRates
}

struct ModelRates: Codable {
    let prompt: String
    let completion: String
    
    var promptPrice: Double {
        Double(prompt) ?? 0.0
    }
    
    var completionPrice: Double {
        Double(completion) ?? 0.0
    }
}

/// Manager class to handle fetching and caching of LLM pricing data
class ModelPricingManager: ObservableObject {
    static let shared = ModelPricingManager()
    
    @Published private(set) var pricingData: ModelPricingData?
    
    private let remoteURL = URL(string: "https://raw.githubusercontent.com/Ebullioscopic/Atoll/feat/dynamic-pricing-workflow/DynamicIsland/managers/LLMUsage/pricing.json")!
    
    private init() {
        loadInitialPricing()
        Task {
            await fetchRemotePricing()
        }
    }
    
    /// Loads initial pricing from local bundle fallback
    private func loadInitialPricing() {
        if let localURL = Bundle.main.url(forResource: "pricing", withExtension: "json", subdirectory: "DynamicIsland/managers/LLMUsage") {
            do {
                let data = try Data(contentsOf: localURL)
                self.pricingData = try JSONDecoder().decode(ModelPricingData.self, from: data)
                print("✅ ModelPricingManager: Loaded bundled pricing fallback")
            } catch {
                print("❌ ModelPricingManager: Failed to load bundled pricing: \(error)")
            }
        } else {
            // Check flat manager path if subdirectory lookup fails
            if let localURL = Bundle.main.url(forResource: "pricing", withExtension: "json") {
                do {
                    let data = try Data(contentsOf: localURL)
                    self.pricingData = try JSONDecoder().decode(ModelPricingData.self, from: data)
                    print("✅ ModelPricingManager: Loaded bundled pricing from flat path")
                } catch {
                    print("❌ ModelPricingManager: Failed to load bundled pricing (flat): \(error)")
                }
            }
        }
    }
    
    /// Asynchronously fetches dynamic pricing from GitHub
    func fetchRemotePricing() async {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .useProtocolCachePolicy
        let session = URLSession(configuration: configuration)
        
        do {
            let (data, response) = try await session.data(from: remoteURL)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("⚠️ ModelPricingManager: Remote fetch returned non-200 status")
                return
            }
            
            let decoded = try JSONDecoder().decode(ModelPricingData.self, from: data)
            
            await MainActor.run {
                self.pricingData = decoded
                print("✅ ModelPricingManager: Successfully updated pricing from remote")
            }
        } catch {
            print("⚠️ ModelPricingManager: Failed to fetch remote pricing (using local/cached): \(error)")
        }
    }
    
    /// Resolves pricing for a specific model ID.
    ///
    /// Usage logs from Claude Code carry native Anthropic ids such as
    /// "claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5-20251001", or
    /// occasionally a provider-prefixed "anthropic/claude-4.8-opus-20260528". The
    /// dynamic pricing table, however, is keyed OpenRouter-style
    /// ("anthropic/claude-3-5-sonnet"). A strict `id == modelId` compare therefore
    /// misses models that ARE in the table but written in a different form, leaving
    /// their cost at 0. We reconcile the purely cosmetic differences — provider
    /// prefix, trailing date stamp, family/version word order, and dot-vs-dash minor
    /// versions — before giving up. This never fabricates a price for a model the
    /// table has no entry for; those stay unpriced and are surfaced explicitly in the
    /// UI rather than shown as a misleading "$0.00".
    func getPricing(for modelId: String) -> (prompt: Double, completion: Double)? {
        guard let models = pricingData?.models else { return nil }
        for key in Self.pricingKeyCandidates(for: modelId) {
            guard let model = models.first(where: { $0.id.lowercased() == key }) else { continue }
            let prompt = model.pricing.promptPrice
            let completion = model.pricing.completionPrice
            // Skip placeholder/incomplete rows (present in the sparse bundled fallback):
            // a genuine Claude price has both a prompt and a completion rate, so require
            // both to be positive. A row with only one side set is treated as unpriced —
            // keep scanning candidates rather than report a half or false "$0.00" price.
            guard prompt > 0, completion > 0 else { continue }
            return (prompt, completion)
        }
        return nil
    }

    /// Ordered, de-duplicated list of lower-cased table keys to try for a raw log id.
    /// OpenRouter's own Claude naming is inconsistent (version-first "claude-3-5-sonnet"
    /// for 3.x, family-first "claude-opus-4" for 4.x), so rather than assume one canonical
    /// form we emit both word orders, each with and without the "anthropic/" prefix, and
    /// let the first that exists in the table win.
    static func pricingKeyCandidates(for raw: String) -> [String] {
        var out: [String] = []
        func push(_ s: String) {
            guard !s.isEmpty else { return }
            for form in [s, "anthropic/\(s)"] where !out.contains(form) { out.append(form) }
        }

        var s = raw.lowercased()
        if let slash = s.lastIndex(of: "/") { s = String(s[s.index(after: slash)...]) } // drop provider prefix
        push(s)

        // Drop a trailing date stamp like "-20260528".
        let noDate = s.replacingOccurrences(of: #"-\d{6,}$"#, with: "", options: .regularExpression)
        push(noDate)

        // Treat dotted minor versions ("4.8") the same as dashed ("4-8").
        let dashed = noDate.replacingOccurrences(of: ".", with: "-")
        push(dashed)

        // Reconcile family/version word order around the "claude-" stem.
        let families = ["opus", "sonnet", "haiku"]
        var tokens = dashed.split(separator: "-").map(String.init)
        if tokens.first == "claude", let famIdx = tokens.firstIndex(where: { families.contains($0) }) {
            let family = tokens.remove(at: famIdx)
            let version = Array(tokens.dropFirst()) // everything after "claude" minus the family token
            if !version.isEmpty {
                push((["claude", family] + version).joined(separator: "-")) // family-first
                push((["claude"] + version + [family]).joined(separator: "-")) // version-first
            }
        }
        return out
    }
}
