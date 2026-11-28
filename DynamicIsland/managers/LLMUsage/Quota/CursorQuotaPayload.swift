import Foundation

struct CursorQuotaPayload: Equatable {
    let cursorModelsUsedPercent: Double?
    let otherModelsUsedPercent: Double?
    let combinedUsedPercent: Double?
    let resetsAt: Date?

    static func decode(_ data: Data) throws -> CursorQuotaPayload {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let planUsage = response.planUsage ?? response.individualUsage?.plan,
              planUsage.autoPercentUsed != nil
                || planUsage.apiPercentUsed != nil
                || planUsage.totalPercentUsed != nil
        else {
            throw CursorQuotaPayloadError.missingPlanUsage
        }
        return CursorQuotaPayload(
            cursorModelsUsedPercent: planUsage.autoPercentUsed?.value,
            otherModelsUsedPercent: planUsage.apiPercentUsed?.value,
            combinedUsedPercent: planUsage.totalPercentUsed?.value,
            resetsAt: response.billingCycleEnd?.date
        )
    }

    private struct Response: Decodable {
        let planUsage: PlanUsage?
        let individualUsage: IndividualUsage?
        let billingCycleEnd: FlexibleDate?

        private enum CodingKeys: String, CodingKey {
            case planUsage
            case individualUsage
            case billingCycleEnd
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            planUsage = try? container.decode(PlanUsage.self, forKey: .planUsage)
            individualUsage = try? container.decode(IndividualUsage.self, forKey: .individualUsage)
            billingCycleEnd = try? container.decode(FlexibleDate.self, forKey: .billingCycleEnd)
        }
    }

    private struct IndividualUsage: Decodable {
        let plan: PlanUsage?
    }

    private struct PlanUsage: Decodable {
        let autoPercentUsed: FlexibleDouble?
        let apiPercentUsed: FlexibleDouble?
        let totalPercentUsed: FlexibleDouble?
    }

    private struct FlexibleDouble: Decodable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self.value = value
                return
            }
            if let text = try? container.decode(String.self), let value = Double(text) {
                self.value = value
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a number or numeric string"
            )
        }
    }

    private struct FlexibleDate: Decodable {
        let date: Date

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                date = Self.date(fromUnixValue: value)
                return
            }
            if let text = try? container.decode(String.self) {
                if let value = Double(text) {
                    date = Self.date(fromUnixValue: value)
                    return
                }
                let fractionalFormatter = ISO8601DateFormatter()
                fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = fractionalFormatter.date(from: text) {
                    date = parsed
                    return
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                if let parsed = formatter.date(from: text) {
                    date = parsed
                    return
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected Unix time or an ISO-8601 date"
            )
        }

        private static func date(fromUnixValue value: Double) -> Date {
            let seconds = abs(value) >= 100_000_000_000 ? value / 1_000 : value
            return Date(timeIntervalSince1970: seconds)
        }
    }
}

enum CursorQuotaPayloadError: LocalizedError {
    case missingPlanUsage

    var errorDescription: String? {
        "Cursor usage response did not include plan usage"
    }
}
