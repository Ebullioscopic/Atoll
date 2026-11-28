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

/// Utility to resolve LLM model pricing dynamically
struct ModelPricing {
    /// Resolves prompt and completion rates for a given model
    /// Rates are per 1M tokens or as defined by the pricing.json structure
    static func resolveRates(for modelId: String) -> (prompt: Double, completion: Double) {
        // Try to get dynamic rates from the manager (Remote or Local Bundled Fallback)
        if let dynamicRates = ModelPricingManager.shared.getPricing(for: modelId) {
            return (dynamicRates.prompt, dynamicRates.completion)
        }
        
        // If the manager has no data (e.g. initialization failed),
        // use a static safe default to avoid 0.0 calculations.
        return (0.000002, 0.000002)
    }

    /// Calculates the total cost for a given model and token counts. Returns nil if the model is unpriced.
    ///
    /// `inputTokens` are the prompt tokens billed at the full prompt rate (i.e. excluding
    /// cache hits and cache writes). Cache reads and writes are priced at the provider's
    /// cache rates when the table has them, and at the plain prompt rate otherwise — the
    /// same over-estimate the app produced before cache rates were tracked.
    static func cost(model: String, inputTokens: Int, outputTokens: Int,
                     cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0) -> Double? {
        guard let rates = ModelPricingManager.shared.getPricing(for: model) else {
            return nil
        }
        let cacheRead = rates.cacheRead ?? rates.prompt
        let cacheWrite = rates.cacheWrite ?? rates.prompt
        return (Double(inputTokens) * rates.prompt)
            + (Double(cacheReadTokens) * cacheRead)
            + (Double(cacheWriteTokens) * cacheWrite)
            + (Double(outputTokens) * rates.completion)
    }
}
