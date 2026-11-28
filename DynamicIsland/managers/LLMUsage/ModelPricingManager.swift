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
    /// Per-token price for prompt tokens served from the provider's cache; absent
    /// or empty when the provider publishes no cache discount for the model.
    let cacheRead: String?
    /// Per-token price for writing prompt tokens into the cache.
    let cacheWrite: String?

    enum CodingKeys: String, CodingKey {
        case prompt, completion
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }

    init(prompt: String, completion: String, cacheRead: String? = nil, cacheWrite: String? = nil) {
        self.prompt = prompt
        self.completion = completion
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
    
    var promptPrice: Double {
        Double(prompt) ?? 0.0
    }
    
    var completionPrice: Double {
        Double(completion) ?? 0.0
    }

    /// nil only when the rate is absent, empty or unparseable, so callers can fall back
    /// to the plain prompt rate. A published "0" is a real rate: OpenRouter uses it for
    /// cache operations that are free.
    var cacheReadPrice: Double? { Self.rate(cacheRead) }
    var cacheWritePrice: Double? { Self.rate(cacheWrite) }

    private static func rate(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty, let value = Double(raw), value >= 0 else { return nil }
        return value
    }
}

/// Fully resolved per-token rates for one model.
struct ResolvedModelRates {
    let prompt: Double
    let completion: Double
    let cacheRead: Double?
    let cacheWrite: Double?
}

/// Manager class to handle fetching and caching of LLM pricing data
class ModelPricingManager: ObservableObject {
    static let shared = ModelPricingManager()
    
    @Published private(set) var pricingData: ModelPricingData?
    
    // Read the copy the update-pricing workflow maintains: it runs on, and pushes back
    // to, the repository's default branch.
    private let remoteURL = URL(string: "https://raw.githubusercontent.com/Ebullioscopic/Atoll/dev/DynamicIsland/managers/LLMUsage/pricing.json")!
    
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
                // The remote table can lag behind the bundled one (it is regenerated by a
                // workflow that only tracks a fixed model list), so merge rather than replace:
                // remote rows with real prices win, bundled rows fill in everything else.
                self.pricingData = Self.merge(bundled: self.pricingData, remote: decoded)
                print("✅ ModelPricingManager: Successfully merged pricing from remote")
            }
        } catch {
            print("⚠️ ModelPricingManager: Failed to fetch remote pricing (using local/cached): \(error)")
        }
    }
    
    /// Overlays `remote` onto `bundled`, keyed by lower-cased id. A remote row only
    /// replaces a bundled row when it carries usable (positive) rates.
    static func merge(bundled: ModelPricingData?, remote: ModelPricingData) -> ModelPricingData {
        guard let bundled else { return remote }
        var byId: [String: ModelPriceEntry] = [:]
        var order: [String] = []
        for m in bundled.models {
            let k = m.id.lowercased()
            if byId[k] == nil { order.append(k) }
            byId[k] = m
        }
        for m in remote.models {
            let k = m.id.lowercased()
            let usable = m.pricing.promptPrice > 0 && m.pricing.completionPrice > 0
            guard let existing = byId[k] else {
                order.append(k)
                byId[k] = m
                continue
            }
            guard usable else { continue }
            // A remote row that predates cache rates must not erase the bundled ones:
            // take the remote prompt/completion prices and fill cache rates field by field.
            let merged = ModelRates(
                prompt: m.pricing.prompt,
                completion: m.pricing.completion,
                cacheRead: m.pricing.cacheReadPrice != nil ? m.pricing.cacheRead : existing.pricing.cacheRead,
                cacheWrite: m.pricing.cacheWritePrice != nil ? m.pricing.cacheWrite : existing.pricing.cacheWrite
            )
            byId[k] = ModelPriceEntry(id: m.id, name: m.name.isEmpty ? existing.name : m.name, pricing: merged)
        }
        let newest = [bundled.lastUpdated, remote.lastUpdated].compactMap { $0 }.max()
        return ModelPricingData(models: order.compactMap { byId[$0] }, lastUpdated: newest)
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
    func getPricing(for modelId: String) -> ResolvedModelRates? {
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
            return ResolvedModelRates(prompt: prompt, completion: completion,
                                      cacheRead: model.pricing.cacheReadPrice, cacheWrite: model.pricing.cacheWritePrice)
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
            for form in [s, "anthropic/\(s)", "openai/\(s)", "google/\(s)"] where !out.contains(form) { out.append(form) }
        }

        var s = raw.lowercased()
        if let slash = s.lastIndex(of: "/") { s = String(s[s.index(after: slash)...]) } // drop provider prefix
        push(s)

        // Drop a trailing date stamp like "-20260528".
        let noDate = s.replacingOccurrences(of: #"-\d{6,}$"#, with: "", options: .regularExpression)
        push(noDate)

        // Treat dotted minor versions ("4.8") the same as dashed ("4-8"), and vice versa:
        // Claude Code logs "claude-fable-5-1" while OpenRouter keys it "claude-fable-5.1".
        let dashed = noDate.replacingOccurrences(of: ".", with: "-")
        push(dashed)
        let dotted = dashed.replacingOccurrences(of: #"(\d)-(\d)"#, with: "$1.$2", options: .regularExpression)
        push(dotted)

        // Antigravity names Gemini models by tier ("gemini-3.7-flash-high") and OpenRouter
        // lists some only as previews ("google/gemini-3.1-pro-preview"); try both without
        // the tier suffix and with a "-preview" suffix.
        let untiered = dotted.replacingOccurrences(of: #"-(low|medium|high|thinking)$"#, with: "", options: .regularExpression)
        push(untiered)
        push(untiered + "-preview")

        // Reconcile family/version word order around the "claude-" stem.
        let families = ["opus", "sonnet", "haiku", "fable"]
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
