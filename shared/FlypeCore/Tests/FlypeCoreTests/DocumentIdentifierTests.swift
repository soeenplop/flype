import Foundation
import XCTest

@testable import FlypeCore

final class DocumentIdentifierTests: XCTestCase {
    func testUnattachedProxyReturnsNilInsteadOfTrapping() {
        let proxy = DeferredDocumentProxy()
        XCTAssertNil(DocumentIdentifier.read(from: proxy))
        let id = UUID()
        proxy.documentIdentifier = id as NSUUID
        XCTAssertEqual(DocumentIdentifier.read(from: proxy), id)
        proxy.documentIdentifier = nil
        XCTAssertNil(DocumentIdentifier.read(from: proxy))
    }
    func testObjectWithoutGetterReturnsNil() {
        XCTAssertNil(DocumentIdentifier.read(from: NSObject()))
    }
    func testUnexpectedGetterValueIsRejected() {
        XCTAssertNil(DocumentIdentifier.read(from: WrongDocumentProxy()))
    }
}

private final class DeferredDocumentProxy: NSObject {
    @objc var documentIdentifier: NSUUID?
}
private final class WrongDocumentProxy: NSObject {
    @objc var documentIdentifier: NSString { "not-a-uuid" }
}
