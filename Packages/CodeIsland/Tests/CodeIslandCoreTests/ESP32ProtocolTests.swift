import XCTest
@testable import CodeIslandCore

final class ESP32ProtocolTests: XCTestCase {
    // MARK: - Source folding

    func testMascotIDFoldsAllCanonicalSources() {
        let pairs: [(String, MascotID)] = [
            ("claude", .claude), ("codex", .codex), ("gemini", .gemini),
            ("cursor", .cursor), ("copilot", .copilot),
            ("trae", .trae), ("traecn", .trae), ("traecli", .trae),
            ("qoder", .qoder),
            ("droid", .droid), ("factory", .droid),
            ("codebuddy", .codebuddy), ("codybuddycn", .codebuddy),
            ("stepfun", .stepfun), ("opencode", .opencode),
            ("qwen", .qwen), ("qwen-code", .qwen),
            ("antigravity", .antigravity), ("ag", .antigravity),
            ("workbuddy", .workbuddy), ("hermes", .hermes),
            ("kimi", .kimi),
        ]
        for (name, expected) in pairs {
            XCTAssertEqual(MascotID(sourceName: name), expected, "source=\(name)")
        }
    }

    func testMascotIDReturnsNilForUnknownSource() {
        XCTAssertNil(MascotID(sourceName: nil))
        XCTAssertNil(MascotID(sourceName: ""))
        XCTAssertNil(MascotID(sourceName: "not-a-real-agent"))
    }

    // MARK: - Status mapping

    func testStatusCodeMapping() {
        XCTAssertEqual(MascotStatusCode(.idle).rawValue, 0)
        XCTAssertEqual(MascotStatusCode(.processing).rawValue, 1)
        XCTAssertEqual(MascotStatusCode(.running).rawValue, 2)
        XCTAssertEqual(MascotStatusCode(.waitingApproval).rawValue, 3)
        XCTAssertEqual(MascotStatusCode(.waitingQuestion).rawValue, 4)
    }

    // MARK: - Frame encoding

    func testEncodeMinimalFrameHasThreeBytes() {
        let frame = MascotFramePayload(mascot: .copilot, status: .waitingApproval)
        let data = frame.encode()
        XCTAssertEqual(Array(data), [4, 3, 0])
    }

    func testEncodeWithShortToolName() {
        let frame = MascotFramePayload(mascot: .claude, status: .running, toolName: "Bash")
        let data = frame.encode()
        XCTAssertEqual(data[0], 0)
        XCTAssertEqual(data[1], 2)
        XCTAssertEqual(data[2], 4)
        XCTAssertEqual(data.count, 3 + 4)
        XCTAssertEqual(String(data: data.subdata(in: 3..<data.count), encoding: .utf8), "Bash")
    }

    func testEncodeTruncatesToolNameToSeventeenBytes() {
        let long = "ThisIsAVeryLongToolName_WayPast17Bytes"
        let frame = MascotFramePayload(mascot: .gemini, status: .processing, toolName: long)
        let data = frame.encode()
        XCTAssertLessThanOrEqual(data.count, ESP32Protocol.maxFrameBytes)
        XCTAssertEqual(data[2], UInt8(ESP32Protocol.maxToolNameBytes))
        XCTAssertEqual(data.count, 3 + ESP32Protocol.maxToolNameBytes)
        // First 17 bytes of the UTF-8 must match.
        let expected = Array(long.utf8.prefix(ESP32Protocol.maxToolNameBytes))
        XCTAssertEqual(Array(data.suffix(ESP32Protocol.maxToolNameBytes)), expected)
    }

    func testEncodeEmptyToolNameIsTreatedAsNone() {
        let frame = MascotFramePayload(mascot: .kimi, status: .idle, toolName: "")
        XCTAssertEqual(Array(frame.encode()), [15, 0, 0])
    }

    func testEncodeBrightnessConfigFrame() {
        let frame = BuddyBrightnessPayload(percent: UInt8(64))
        XCTAssertEqual(Array(frame.encode()), [ESP32Protocol.brightnessFrameMarker, 64])
    }

    func testBrightnessConfigClampsToSupportedRange() {
        XCTAssertEqual(BuddyBrightnessPayload(percent: 1.0).percent, ESP32Protocol.minBrightnessPercent)
        XCTAssertEqual(BuddyBrightnessPayload(percent: 150.0).percent, ESP32Protocol.maxBrightnessPercent)
        XCTAssertEqual(BuddyBrightnessPayload(percent: Double.nan).percent, ESP32Protocol.defaultBrightnessPercent)
    }

    func testEncodeScreenOrientationConfigFrame() {
        XCTAssertEqual(
            Array(BuddyScreenOrientationPayload(orientation: .up).encode()),
            [ESP32Protocol.orientationFrameMarker, 0]
        )
        XCTAssertEqual(
            Array(BuddyScreenOrientationPayload(orientation: .down).encode()),
            [ESP32Protocol.orientationFrameMarker, 1]
        )
    }

    func testEncodeWorkspaceFrame() {
        let frame = BuddyWorkspacePayload(workspaceName: "CodeIsland")
        let data = frame.encode()
        XCTAssertEqual(data[0], ESP32Protocol.workspaceFrameMarker)
        XCTAssertEqual(data[1], 10)
        XCTAssertEqual(String(data: data.subdata(in: 2..<data.count), encoding: .utf8), "CodeIsland")
    }

    func testEncodeMessagePreviewFrame() {
        let frame = BuddyMessagePreviewPayload(index: 1, total: 3, isUser: true, text: "Need help")
        let data = frame.encode()
        XCTAssertEqual(data[0], ESP32Protocol.messagePreviewFrameMarker)
        XCTAssertEqual(data[1], 1)
        XCTAssertEqual(data[2], 3)
        XCTAssertEqual(data[3] & 0x80, 0x80)
        XCTAssertEqual(data[3] & 0x7F, 9)
        XCTAssertEqual(String(data: data.subdata(in: 4..<data.count), encoding: .utf8), "Need help")
    }

    func testMessagePreviewPayloadPreservesBoundarySpacesInsideSegment() {
        let frame = BuddyMessagePreviewPayload(index: 0, total: 2, isUser: false, text: "generated ")

        XCTAssertEqual(frame.text, "generated ")
        XCTAssertEqual(String(data: frame.encode().subdata(in: 4..<frame.encode().count), encoding: .utf8), "generated ")
    }

    func testScreenOrientationDefaultsToUpForUnknownValues() {
        XCTAssertEqual(BuddyScreenOrientation(settingsValue: "down"), .down)
        XCTAssertEqual(BuddyScreenOrientation(settingsValue: "sideways"), .up)
        XCTAssertEqual(BuddyScreenOrientation(wireValue: 1), .down)
        XCTAssertEqual(BuddyScreenOrientation(wireValue: 7), .up)
    }

    func testConvenienceInitFromSourceString() {
        let frame = MascotFramePayload(source: "factory", status: .running, toolName: "Edit")
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.mascot, .droid)
        XCTAssertEqual(frame?.status, .running)
    }

    func testConvenienceInitReturnsNilForUnknownSource() {
        XCTAssertNil(MascotFramePayload(source: "bogus", status: .idle))
    }

    func testBuddyUplinkEventParsesControlCommands() {
        XCTAssertEqual(BuddyUplinkEvent(payload: Data([0xF0])), .command(.approveCurrentPermission))
        XCTAssertEqual(BuddyUplinkEvent(payload: Data([0xF1])), .command(.denyCurrentPermission))
        XCTAssertEqual(BuddyUplinkEvent(payload: Data([0xF2])), .command(.skipCurrentQuestion))
    }

    // MARK: - All 16 × 5 round-trip sanity

    func testAllMascotStatusCombinationsEncodeWithinLimits() {
        for mascot in MascotID.allCases {
            for statusRaw: UInt8 in 0...4 {
                let status = MascotStatusCode(rawValue: statusRaw)!
                let data = MascotFramePayload(mascot: mascot, status: status, toolName: "abc").encode()
                XCTAssertEqual(data[0], mascot.rawValue)
                XCTAssertEqual(data[1], statusRaw)
                XCTAssertEqual(data[2], 3)
                XCTAssertEqual(data.count, 6)
            }
        }
    }

    // MARK: - Model frame encoding

    func testEncodeModelFrame() {
        let frame = BuddyModelPayload(modelName: "opus")
        let data = frame.encode()
        XCTAssertEqual(data[0], ESP32Protocol.modelFrameMarker)
        XCTAssertEqual(data[1], 4)
        XCTAssertEqual(String(data: data.subdata(in: 2..<data.count), encoding: .utf8), "opus")
    }

    func testEncodeModelFrameNil() {
        let frame = BuddyModelPayload(modelName: nil)
        let data = frame.encode()
        XCTAssertEqual(Array(data), [ESP32Protocol.modelFrameMarker, 0])
    }

    func testEncodeModelFrameTruncates() {
        let long = String(repeating: "a", count: 30)
        let frame = BuddyModelPayload(modelName: long)
        let data = frame.encode()
        XCTAssertEqual(data[1], UInt8(ESP32Protocol.maxModelNameBytes))
        XCTAssertEqual(data.count, 2 + ESP32Protocol.maxModelNameBytes)
    }

    // MARK: - Stats frame encoding

    func testEncodeStatsFrame() {
        let frame = BuddyStatsPayload(activeSessionCount: 2, totalSessionCount: 5, toolCallCount: 47, sessionDurationMinutes: 23)
        let data = frame.encode()
        XCTAssertEqual(data[0], ESP32Protocol.statsFrameMarker)
        XCTAssertEqual(data[1], 2)
        XCTAssertEqual(data[2], 5)
        XCTAssertEqual(UInt16(data[3]) << 8 | UInt16(data[4]), 47)
        XCTAssertEqual(data[5], 23)
        XCTAssertEqual(data.count, 6)
    }

    func testEncodeStatsFrameClampsValues() {
        let frame = BuddyStatsPayload(activeSessionCount: 300, totalSessionCount: -1, toolCallCount: 70000, sessionDurationMinutes: 999)
        XCTAssertEqual(frame.activeSessionCount, 255)
        XCTAssertEqual(frame.totalSessionCount, 0)
        XCTAssertEqual(frame.toolCallCount, 65535)
        XCTAssertEqual(frame.sessionDurationMinutes, 255)
    }

    // MARK: - Subagent frame encoding

    func testEncodeSubagentFrame() {
        let frame = BuddySubagentPayload(count: 3)
        let data = frame.encode()
        XCTAssertEqual(Array(data), [ESP32Protocol.subagentFrameMarker, 3])
    }

    func testEncodeSubagentFrameClampsToFifteen() {
        let frame = BuddySubagentPayload(count: 20)
        XCTAssertEqual(frame.count, 15)
    }

    // MARK: - Event frame encoding

    func testEncodeEventFrame() {
        XCTAssertEqual(Array(BuddyEventPayload.complete.encode()), [ESP32Protocol.eventFrameMarker, 1])
        XCTAssertEqual(Array(BuddyEventPayload.error.encode()), [ESP32Protocol.eventFrameMarker, 2])
    }

    // MARK: - Time hint frame encoding

    func testEncodeTimeHintFrame() {
        let frame = BuddyTimeHintPayload(hour: 14)
        XCTAssertEqual(Array(frame.encode()), [ESP32Protocol.timeHintFrameMarker, 14])
    }

    func testEncodeTimeHintFrameClampsRange() {
        XCTAssertEqual(BuddyTimeHintPayload(hour: 25).hour, 23)
        XCTAssertEqual(BuddyTimeHintPayload(hour: -1).hour, 0)
    }

    // MARK: - Tool history frame encoding

    func testEncodeToolHistoryFrame() {
        let frame = BuddyToolHistoryPayload(index: 0, success: true, toolName: "Bash")
        let data = frame.encode()
        XCTAssertEqual(data[0], ESP32Protocol.toolHistoryFrameMarker)
        XCTAssertEqual(data[1], 0)
        XCTAssertEqual(data[2] & 0x80, 0x80)
        XCTAssertEqual(data[2] & 0x7F, 4)
        XCTAssertEqual(String(data: data.subdata(in: 3..<data.count), encoding: .utf8), "Bash")
    }

    func testEncodeToolHistoryFrameFailure() {
        let frame = BuddyToolHistoryPayload(index: 2, success: false, toolName: "Edit")
        let data = frame.encode()
        XCTAssertEqual(data[2] & 0x80, 0x00)
    }

    func testEncodeToolHistoryFrameTruncatesName() {
        let long = "VeryLongToolNameThatExceeds"
        let frame = BuddyToolHistoryPayload(index: 0, success: true, toolName: long)
        let data = frame.encode()
        let nameLen = data[2] & 0x7F
        XCTAssertEqual(nameLen, UInt8(ESP32Protocol.maxToolHistoryNameBytes))
    }

    func testEncodeToolHistoryClearFrame() {
        XCTAssertEqual(
            Array(BuddyToolHistoryClearPayload().encode()),
            [ESP32Protocol.toolHistoryFrameMarker, 0, 0]
        )
    }

    // MARK: - Pair request frame encoding

    func testEncodePairRequestFrame() {
        let hostId = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let frame = BuddyPairRequestPayload(hostId: hostId)
        let data = frame.encode()
        XCTAssertEqual(data.count, ESP32Protocol.pairRequestFrameBytes)
        XCTAssertEqual(data[0], ESP32Protocol.pairRequestMarker)
        XCTAssertEqual(Array(data.suffix(6)), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    }

    func testPairRequestPadsShortHostId() {
        let shortId = Data([0x01, 0x02])
        let frame = BuddyPairRequestPayload(hostId: shortId)
        let data = frame.encode()
        XCTAssertEqual(data.count, ESP32Protocol.pairRequestFrameBytes)
        XCTAssertEqual(Array(data.suffix(6)), [0x01, 0x02, 0x00, 0x00, 0x00, 0x00])
    }

    func testPairRequestTruncatesLongHostId() {
        let longId = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let frame = BuddyPairRequestPayload(hostId: longId)
        let data = frame.encode()
        XCTAssertEqual(data.count, ESP32Protocol.pairRequestFrameBytes)
        XCTAssertEqual(Array(data.suffix(6)), [0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
    }

    // MARK: - Unpair frame encoding

    func testEncodeUnpairFrame() {
        let hostId = Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
        let frame = BuddyUnpairPayload(hostId: hostId)
        let data = frame.encode()
        XCTAssertEqual(data.count, ESP32Protocol.unpairFrameBytes)
        XCTAssertEqual(data[0], ESP32Protocol.unpairMarker)
        XCTAssertEqual(Array(data.suffix(6)), [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
    }

    // MARK: - Uplink pairing response parsing

    func testBuddyUplinkEventParsesPairAccepted() {
        let event = BuddyUplinkEvent(payload: Data([ESP32Protocol.pairAcceptedMarker]))
        XCTAssertEqual(event, .pairResponse(.accepted))
    }

    func testBuddyUplinkEventParsesPairRejected() {
        let event = BuddyUplinkEvent(payload: Data([ESP32Protocol.pairRejectedMarker]))
        XCTAssertEqual(event, .pairResponse(.rejected))
    }

    func testBuddyUplinkEventParsesPairPending() {
        let event = BuddyUplinkEvent(payload: Data([ESP32Protocol.pairPendingMarker]))
        XCTAssertEqual(event, .pairResponse(.pending))
    }

    func testBuddyUplinkEventEmptyPayloadReturnsNil() {
        XCTAssertNil(BuddyUplinkEvent(payload: Data()))
    }
}
