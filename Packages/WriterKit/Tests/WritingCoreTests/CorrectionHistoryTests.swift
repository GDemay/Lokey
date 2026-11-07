import XCTest
@testable import WritingCore

final class CorrectionHistoryTests: XCTestCase {
    func testExtractsEditsFromMultipleLanguagesAndOmitsUnchangedText() {
        let before = "She have two dogs in the garden. Je peut venir demain."
        let after = "She has two dogs in the garden. Je peux venir demain."
        let edits = CorrectionExample.extract(from: before, corrected: after)
        XCTAssertEqual(edits.map(\.before), ["She have", "Je peut"])
        XCTAssertEqual(edits.map(\.after), ["She has", "Je peux"])
        XCTAssertEqual(edits.map(\.languageCode), ["en", "fr"])
        XCTAssertEqual(edits.map(\.lesson), [.agreement, .frenchAgreement])
        XCTAssertTrue(CorrectionExample.extract(from: after, corrected: after).isEmpty)
    }

    func testRecordsEditsInOtherLanguagesAndKeepsPunctuation() {
        let edits = CorrectionExample.extract(from: "Esto es mui importante", corrected: "Esto es muy importante",
                                              languageHint: "es")
        XCTAssertEqual(edits.first?.before, "mui")
        XCTAssertEqual(edits.first?.after, "muy")
        XCTAssertEqual(edits.first?.languageCode, "es")
        XCTAssertEqual(edits.first?.lesson, .other)
        let punctuation = CorrectionExample.extract(from: "See you soon", corrected: "See you soon.")
        XCTAssertEqual(punctuation.first?.after, ".")
        XCTAssertEqual(punctuation.first?.lesson, .punctuation)
        XCTAssertTrue(CorrectionExample.extract(from: "I don't know", corrected: "I don’t know").isEmpty)
    }

    func testStoresOnlyExamplesAndRemovesOnlyTheUndoneEvent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CorrectionHistory(directory: folder)
        XCTAssertTrue(try store.items().isEmpty)
        let first = UUID(), second = UUID()
        let firstDate = Date(timeIntervalSince1970: 1)
        let secondDate = Date(timeIntervalSince1970: 2)
        try store.record(id: first, date: firstDate, original: "She have a dog named Luna",
                         corrected: "She has a dog named Luna")
        try store.record(id: second, date: secondDate, original: "She have two cats",
                         corrected: "She has two cats")
        let items = try store.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.count, 2)
        XCTAssertEqual(items.first?.lastSeen, secondDate)
        let stored = try String(contentsOf: folder.appendingPathComponent(first.uuidString + ".json"), encoding: .utf8)
        XCTAssertFalse(stored.contains("Luna"))
        try store.remove(second)
        try store.remove(second)
        XCTAssertEqual(try store.items().first?.count, 1)
        XCTAssertEqual(try store.items().first?.lastSeen, firstDate)
        try store.clear()
        XCTAssertTrue(try store.items().isEmpty)
    }
}
