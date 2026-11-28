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

import XCTest

@testable import Atoll

/// The Screen Assistant's OpenAI provider can point at any OpenAI-compatible server (#807).
final class OpenAICompatibleEndpointTests: XCTestCase {
    private func url(_ base: String) -> String? {
        OpenAICompatibleEndpoint.chatCompletionsURL(baseURL: base)?.absoluteString
    }

    func testEmptyBaseURLMeansOpenAI() {
        XCTAssertEqual(url(""), "https://api.openai.com/v1/chat/completions")
        XCTAssertTrue(OpenAICompatibleEndpoint.isDefault("  "))
        XCTAssertTrue(OpenAICompatibleEndpoint.isDefault("https://api.openai.com/v1/"))
    }

    func testAppendsChatCompletionsToABase() {
        XCTAssertEqual(url("http://localhost:1234/v1/"), "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(url(" https://proxy.example.com/openai/v1 "), "https://proxy.example.com/openai/v1/chat/completions")
        XCTAssertFalse(OpenAICompatibleEndpoint.isDefault("http://localhost:1234/v1"))
    }

    func testKeepsAFullEndpoint() {
        XCTAssertEqual(url("https://proxy.example.com/v1/chat/completions"), "https://proxy.example.com/v1/chat/completions")
    }

    func testRejectsNonHTTPValues() {
        XCTAssertNil(url("localhost:1234"))
        XCTAssertNil(url("ftp://example.com/v1"))
        XCTAssertNil(url("not a url"))
    }
}
