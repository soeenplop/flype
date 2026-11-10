import Foundation

/// The two Flype Pro plans. Only the yearly one starts with a free week, once per account.
public enum BillingPeriod: String, Codable, Sendable, CaseIterable {
    case month, year
    public var price: Decimal { self == .month ? Decimal(string: "5.95")! : Decimal(string: "59.95")! }
    public var hasTrial: Bool { self == .year }
    public static let trialDays = 7
}

/// Flype Pro as the server sees it. The apps only show it; the server alone decides what Pro allows.
public struct SubscriptionStatus: Decodable, Sendable, Equatable {
    public enum Source: String, Sendable {
        case direct
        case appStore = "app_store"
        case manual
    }
    public enum State: String, Sendable {
        case trialing, active
        case pastDue = "past_due"
        case canceled
    }
    public let isPro: Bool
    public let source: Source?
    public let state: State?
    public let period: BillingPeriod?
    public let willRenew: Bool
    /// End of the trial or paid period, without the server's grace period.
    public let periodEndsAt: Date?
    public let trialAvailable: Bool

    public init(
        isPro: Bool, source: Source? = nil, state: State? = nil, period: BillingPeriod? = nil, willRenew: Bool = false,
        periodEndsAt: Date? = nil, trialAvailable: Bool
    ) {
        self.isPro = isPro
        self.source = source
        self.state = state
        self.period = period
        self.willRenew = willRenew
        self.periodEndsAt = periodEndsAt
        self.trialAvailable = trialAvailable
    }

    enum CodingKeys: String, CodingKey {
        case plan, source, status, period
        case willRenew = "will_renew"
        case periodEndsAt = "period_ends_at"
        case trialAvailable = "trial_available"
    }
    /// Unknown values from a newer server are left out instead of failing the whole status.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPro = try container.decode(String.self, forKey: .plan) == "pro"
        source = try container.decodeIfPresent(String.self, forKey: .source).flatMap(Source.init(rawValue:))
        state = try container.decodeIfPresent(String.self, forKey: .status).flatMap(State.init(rawValue:))
        period = try container.decodeIfPresent(String.self, forKey: .period).flatMap(BillingPeriod.init(rawValue:))
        willRenew = try container.decodeIfPresent(Bool.self, forKey: .willRenew) ?? false
        periodEndsAt = try container.decodeIfPresent(String.self, forKey: .periodEndsAt).flatMap(Self.date)
        trialAvailable = try container.decodeIfPresent(Bool.self, forKey: .trialAvailable) ?? false
    }

    /// PostgreSQL writes microseconds, which the plain ISO 8601 decoding strategy rejects.
    static func date(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
