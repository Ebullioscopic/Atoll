import Foundation

@main
enum CursorQuotaPayloadTests {
    static func main() throws {
        try decodesCurrentBucketPercentages()
        try decodesNumericStrings()
        try decodesUsageSummary()
        try decodesLegacyCombinedPercentage()
        try rejectsMissingPlanUsage()
        print("CursorQuotaPayload tests passed")
    }

    private static func decodesCurrentBucketPercentages() throws {
        let data = Data(#"{"planUsage":{"autoPercentUsed":0.0455,"apiPercentUsed":91.868,"totalPercentUsed":18.41},"billingCycleEnd":"1785932150000"}"#.utf8)
        let payload = try CursorQuotaPayload.decode(data)
        assertEqual(payload.cursorModelsUsedPercent, 0.0455)
        assertEqual(payload.otherModelsUsedPercent, 91.868)
        assertEqual(payload.combinedUsedPercent, 18.41)
        assertEqual(payload.resetsAt?.timeIntervalSince1970, 1_785_932_150)
    }

    private static func decodesNumericStrings() throws {
        let data = Data(#"{"planUsage":{"autoPercentUsed":"1.25","apiPercentUsed":"42.25"},"billingCycleEnd":1785932150000}"#.utf8)
        let payload = try CursorQuotaPayload.decode(data)
        assertEqual(payload.cursorModelsUsedPercent, 1.25)
        assertEqual(payload.otherModelsUsedPercent, 42.25)
        assertEqual(payload.resetsAt?.timeIntervalSince1970, 1_785_932_150)
    }

    private static func decodesUsageSummary() throws {
        let data = Data(#"{"billingCycleEnd":"2026-08-05T12:15:50.000Z","individualUsage":{"plan":{"autoPercentUsed":4.5,"apiPercentUsed":73.5,"totalPercentUsed":20.1}}}"#.utf8)
        let payload = try CursorQuotaPayload.decode(data)
        assertEqual(payload.cursorModelsUsedPercent, 4.5)
        assertEqual(payload.otherModelsUsedPercent, 73.5)
        assertEqual(payload.combinedUsedPercent, 20.1)
        assertEqual(payload.resetsAt?.timeIntervalSince1970, 1_785_932_150)
    }

    private static func decodesLegacyCombinedPercentage() throws {
        let payload = try CursorQuotaPayload.decode(
            Data(#"{"planUsage":{"totalPercentUsed":16.5}}"#.utf8)
        )
        assertEqual(payload.combinedUsedPercent, 16.5)
    }

    private static func rejectsMissingPlanUsage() throws {
        do {
            _ = try CursorQuotaPayload.decode(Data(#"{"billingCycleEnd":"1785932150000"}"#.utf8))
            fatalError("Expected missing plan usage to fail")
        } catch CursorQuotaPayloadError.missingPlanUsage {
            // Expected.
        }
    }

    private static func assertEqual(
        _ actual: Double?,
        _ expected: Double,
        accuracy: Double = 0.001,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let actual, abs(actual - expected) <= accuracy else {
            fatalError("Expected \(expected), got \(String(describing: actual))", file: file, line: line)
        }
    }
}
