import Foundation
import XCTest

@testable import FlypeCore

private final class BillingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == SupabaseAPI.projectURL.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class SubscriptionAPITests: XCTestCase, @unchecked Sendable {
    private func api() -> SupabaseAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BillingProtocol.self]
        return SupabaseAPI(session: URLSession(configuration: config))
    }
    override func tearDown() {
        BillingProtocol.handler = nil
        super.tearDown()
    }
    private static func body(_ request: URLRequest) throws -> [String: String] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(buffer, count: count)
            }
            data = bytes
        }
        return try JSONDecoder().decode([String: String].self, from: XCTUnwrap(data))
    }

    func testStatusDecodesPostgresDatesAndIgnoresUnknownValues() async throws {
        BillingProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/flype_subscription_status")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
            return (
                200,
                Data(
                    #"{"plan":"pro","source":"direct","status":"trialing","period":"year","will_renew":true,"expires_at":"2026-11-20T10:00:00.123456+00:00","period_ends_at":"2026-11-17T10:00:00.123456+00:00","trial_available":false}"#
                        .utf8)
            )
        }
        let status = try await api().subscriptionStatus(token: "unit-test-token")
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.source, .direct)
        XCTAssertEqual(status.state, .trialing)
        XCTAssertEqual(status.period, .year)
        XCTAssertTrue(status.willRenew)
        XCTAssertFalse(status.trialAvailable)
        XCTAssertEqual(status.periodEndsAt?.timeIntervalSince1970 ?? 0, 1_794_909_600.123, accuracy: 0.001)

        let free = try JSONDecoder().decode(
            SubscriptionStatus.self,
            from: Data(
                #"{"plan":"free","source":null,"status":"paused","period":"week","will_renew":null,"expires_at":null,"period_ends_at":"2026-11-17T10:00:00+00:00","trial_available":true}"#
                    .utf8))
        XCTAssertFalse(free.isPro)
        XCTAssertNil(free.source)
        XCTAssertNil(free.state)
        XCTAssertNil(free.period)
        XCTAssertFalse(free.willRenew)
        XCTAssertNotNil(free.periodEndsAt)
        XCTAssertTrue(free.trialAvailable)
    }

    func testBillingPagesAskForThePlanAndOpenOnlyStripe() async throws {
        for (period, expected) in [
            (BillingPeriod?.some(.year), ["action": "checkout", "period": "year"]),
            (.some(.month), ["action": "checkout", "period": "month"]),
            (nil, ["action": "portal"]),
        ] {
            BillingProtocol.handler = { request in
                XCTAssertEqual(request.url?.path, "/functions/v1/billing")
                XCTAssertEqual(try Self.body(request), expected)
                return (200, Data(#"{"url":"https://checkout.stripe.com/c/pay/cs_test"}"#.utf8))
            }
            let url = try await api().billingPage(token: "unit-test-token", period: period)
            XCTAssertEqual(url.host(), "checkout.stripe.com")
        }
        for answer in ["https://stripe.com.example.invalid/x", "http://checkout.stripe.com/x", "flype-mac://billing"] {
            BillingProtocol.handler = { _ in (200, Data(#"{"url":"\#(answer)"}"#.utf8)) }
            do {
                _ = try await api().billingPage(token: "unit-test-token", period: .month)
                XCTFail("\(answer) must not open")
            } catch SupabaseAPI.Failure.rejected {} catch { XCTFail("Wrong error: \(error)") }
        }
    }

    func testFailedCancellationKeepsTheAccount() async throws {
        let session = try JSONDecoder().decode(
            CloudSession.self,
            from: Data(
                #"{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"00000000-0000-0000-0000-000000000001","app_metadata":{"provider":"google"}}}"#
                    .utf8))
        for status in [401, 500, 502, 503] {
            var paths: [String] = []
            BillingProtocol.handler = { request in
                paths.append(request.url!.path)
                return (status, Data())
            }
            do {
                try await api().deleteAccount(session: session)
                XCTFail("Status \(status) must keep the account")
            } catch SupabaseAPI.Failure.subscriptionCancellationUnavailable {} catch {
                XCTFail("Wrong error: \(error)")
            }
            XCTAssertEqual(paths, ["/functions/v1/billing"])
        }
        // Before the billing function is deployed, no subscription can exist.
        var paths: [String] = []
        BillingProtocol.handler = { request in
            paths.append(request.url!.path)
            return request.url!.path.contains("billing") ? (404, Data()) : (200, Data(#"{"deleted":true}"#.utf8))
        }
        try await api().deleteAccount(session: session)
        XCTAssertEqual(paths, ["/functions/v1/billing", "/rest/v1/rpc/flype_delete_account"])
    }
}
