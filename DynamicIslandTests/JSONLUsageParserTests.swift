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
 * You should receive a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import XCTest
@testable import Atoll

final class JSONLUsageParserTests: XCTestCase {

    private func makeTempFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("test_\(UUID().uuidString).jsonl")
        try content.data(using: .utf8)!.write(to: file)
        return file
    }

    private func parseFile(_ file: URL, now: Date) -> UsageSnapshot {
        JSONLUsageParser.aggregate(files: [file], now: now)
    }

    func testParseValidJSONLRecords() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts1 = iso.string(from: now.addingTimeInterval(-3600))
        let ts2 = iso.string(from: now.addingTimeInterval(-7200))

        let content = """
        {"timestamp": "\(ts1)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        {"timestamp": "\(ts2)", "message": {"id": "msg2", "model": "claude-3-sonnet", "usage": {"input_tokens": 200, "output_tokens": 100}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 300)
        XCTAssertEqual(snapshot.session.outputTokens, 150)
        XCTAssertEqual(snapshot.models.count, 2)
    }

    func testParseDeduplicatesByMessageId() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        let content = """
        {"timestamp": "\(ts)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        {"timestamp": "\(ts)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 100)
        XCTAssertEqual(snapshot.session.outputTokens, 50)
        XCTAssertEqual(snapshot.models.count, 1)
    }

    func testRejectsOversizedUnterminatedRecord() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        // Create a valid record followed by a valid JSON record padded
        // beyond the size limit (with a large dummy field), then a newline
        // and another valid record. The oversized record should be
        // excluded; parsing should resume and process the following record.
        let validRecord = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg1\", \"model\": \"claude-3-opus\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}}}"
        let padding = String(repeating: "x", count: 1024 * 1024 + 100)
        let oversizedRecord = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msgOversized\", \"model\": \"claude-3-opus\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}}, \"padding\": \"\(padding)\"}"
        let validRecord2 = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg2\", \"model\": \"claude-3-sonnet\", \"usage\": {\"input_tokens\": 200, \"output_tokens\": 100}}}"
        let content = validRecord + "\n" + oversizedRecord + "\n" + validRecord2

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        // msg1 and msg2 should be parsed; the oversized record should be discarded entirely.
        XCTAssertEqual(snapshot.session.inputTokens, 300)
        XCTAssertEqual(snapshot.session.outputTokens, 150)
        XCTAssertEqual(snapshot.models.count, 2)
    }

    func testParsesAllowedSizeUnterminatedFinalRecord() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        // Create a valid record followed by an allowed-size final line without newline
        let validRecord = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg1\", \"model\": \"claude-3-opus\", \"usage\": {\"input_tokens\": 100, \"output_tokens\": 50}}}"
        let finalLine = "{\"timestamp\": \"\(ts)\", \"message\": {\"id\": \"msg2\", \"model\": \"claude-3-sonnet\", \"usage\": {\"input_tokens\": 200, \"output_tokens\": 100}}}"
        let content = validRecord + "\n" + finalLine // No trailing newline

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        // Both records should be parsed
        XCTAssertEqual(snapshot.session.inputTokens, 300)
        XCTAssertEqual(snapshot.session.outputTokens, 150)
        XCTAssertEqual(snapshot.models.count, 2)
    }

    func testSkipsRecordsOutsideWeekWindow() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldTs = iso.string(from: now.addingTimeInterval(-8 * 86400)) // 8 days ago, outside week
        let recentTs = iso.string(from: now.addingTimeInterval(-3600))

        let content = """
        {"timestamp": "\(oldTs)", "message": {"id": "msg1", "model": "claude-3-opus", "usage": {"input_tokens": 100, "output_tokens": 50}}}
        {"timestamp": "\(recentTs)", "message": {"id": "msg2", "model": "claude-3-sonnet", "usage": {"input_tokens": 200, "output_tokens": 100}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        // Only the recent record should be counted
        XCTAssertEqual(snapshot.week.inputTokens, 200)
        XCTAssertEqual(snapshot.week.outputTokens, 100)
    }

    func testParseCodexTokenCountFormat() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-3600))

        let content = """
        {"type": "event_msg", "timestamp": "\(ts)", "payload": {"type": "token_count", "info": {"last_token_usage": {"input_tokens": 500, "output_tokens": 250}}}}
        """

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 500)
        XCTAssertEqual(snapshot.session.outputTokens, 250)
        XCTAssertTrue(snapshot.models.contains { $0.model == "codex" })
    }

    func testUsagePrefilterKeepsOnlyLinesThatCanCarryTokens() {
        XCTAssertTrue(JSONLUsageParser.mayContainUsage(Data(#"{"message":{"usage":{"input_tokens":1}}}"#.utf8)))
        XCTAssertTrue(JSONLUsageParser.mayContainUsage(Data(#"{"type":"event_msg","payload":{"type":"token_count"}}"#.utf8)))
        XCTAssertTrue(JSONLUsageParser.mayContainUsage(Data(#"{"type":"turn_context","payload":{"model":"gpt-5"}}"#.utf8)))
        XCTAssertFalse(JSONLUsageParser.mayContainUsage(Data(#"{"type":"user","message":{"content":"tool output"}}"#.utf8)))
        XCTAssertTrue(JSONLUsageParser.mayContainUsage(Data(#"{"message":{"\u0075sage":{"input_tokens":1}}}"#.utf8)))
    }

    func testUsageKeySpelledWithUnicodeEscapeIsCounted() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-600))

        let content = #"{"timestamp": "\#(ts)", "message": {"id": "esc1", "model": "claude-3-opus", "\u0075sage": {"input_tokens": 7, "output_tokens": 3}}}"#

        let file = try makeTempFile(content: content)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 7)
        XCTAssertEqual(snapshot.session.outputTokens, 3)
    }

    func testRecordsSpreadAcrossChunksAmongLargeNonUsageLines() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: now.addingTimeInterval(-600))

        // ~40 KB tool-output lines push records across several 64 KB read chunks.
        let filler = #"{"type":"user","message":{"content":""# + String(repeating: "x", count: 40_000) + #""}}"#
        var lines: [String] = []
        for index in 0..<10 {
            lines.append(filler)
            lines.append(#"{"timestamp": "\#(ts)", "message": {"id": "m\#(index)", "model": "claude-3-opus", "usage": {"input_tokens": 10, "output_tokens": 5}}}"#)
        }

        let file = try makeTempFile(content: lines.joined(separator: "\n"))
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = parseFile(file, now: now)

        XCTAssertEqual(snapshot.session.inputTokens, 100)
        XCTAssertEqual(snapshot.session.outputTokens, 50)
    }
}