import XCTest
@testable import WritingCore

final class TextTests: XCTestCase {
    func testOSADistance() {
        XCTAssertEqual(Similarity.osaDistance(Array("teh"), Array("the")), 1)
        XCTAssertEqual(Similarity.osaDistance(Array("recieved"), Array("received")), 1)
        XCTAssertEqual(Similarity.osaDistance(Array(""), Array("abc")), 3)
        XCTAssertEqual(Similarity.osaDistance(Array("kitten"), Array("sitting")), 3)
    }

    func testWordsAndRetention() {
        XCTAssertEqual(Similarity.words("I'm on my way, Café!"), ["im", "on", "my", "way", "café"])
        XCTAssertEqual(Similarity.wordRetention(source: "Their going to the park", output: "They're going to the park"), 1, accuracy: 1e-9)
        XCTAssertLessThan(Similarity.wordRetention(source: "Could you review PR 482 when you have a minute", output: "Sure, I can review it."), 0.6)
    }

    func testDiffRoundTripsAndHighlights() {
        let old = "Their going to the park."
        let new = "They're going to the park!"
        let segments = TextDiff.diff(old, new)
        XCTAssertEqual(segments.filter { $0.kind != .inserted }.map(\.text).joined(), old)
        XCTAssertEqual(segments.filter { $0.kind != .removed }.map(\.text).joined(), new)
        XCTAssertEqual(TextDiff.changes(old, new), ["Their → They're", ". → !"])
        XCTAssertEqual(TextDiff.diff("same", "same"), [TextDiff.Segment(.equal, "same")])
    }

    func testSentenceSplittingKeepsEveryCharacter() {
        let text = "Hi john. how are you?? I'm \"fine\". ok\nnew line here... yes"
        let parts = TextChunker.sentences(text)
        XCTAssertEqual(parts.joined(), text)
        XCTAssertEqual(parts.first, "Hi john. ")
        XCTAssertEqual(parts[1], "how are you?? ")
    }

    func testChunksPreserveWhitespace() {
        let text = "  First sentence here.  Second one!\n\nThird sentence after a blank line.   "
        let chunks = TextChunker.chunks(text, maxCharacters: 25)
        XCTAssertEqual(chunks.map { $0.leading + $0.body + $0.trailing }.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.body.first?.isWhitespace != true && $0.body.last?.isWhitespace != true })
        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testEditPlanMinimalAndCorrect() {
        let doc = SimulatedTextDocument(text: "Hello. Their going home. And")
        // The sentence "Their going home." is followed by " And" before the cursor.
        let steps = EditPlanner.plan(original: "Their going home.", replacement: "They're going home.", tail: " And")
        EditPlanner.apply(steps, to: doc)
        XCTAssertEqual(doc.text, "Hello. They're going home. And")
        XCTAssertEqual(doc.cursor, doc.text.count)
        XCTAssertTrue(steps.contains(.moveCursor(-" going home. And".count)))
    }

    func testEditPlanFallsBackAcrossEmoji() {
        let doc = SimulatedTextDocument(text: "i dont know 🙂 ok")
        let steps = EditPlanner.plan(original: "i dont know 🙂 ok", replacement: "I don't know 🙂 ok")
        XCTAssertFalse(steps.contains { if case .moveCursor = $0 { return true } else { return false } })
        EditPlanner.apply(steps, to: doc)
        XCTAssertEqual(doc.text, "I don't know 🙂 ok")
    }

    func testEditPlanNoopWhenEqual() {
        XCTAssertEqual(EditPlanner.plan(original: "Same.", replacement: "Same."), [])
    }

    func testLiveCorrectionDetectsFinishedSentence() {
        let policy = LiveCorrectionPolicy()
        XCTAssertEqual(policy.completedSentence(in: "Hi. their going to the park. "),
                       PendingCorrection(original: "their going to the park.", tail: " "))
        XCTAssertNil(policy.completedSentence(in: "their going to the park."), "no space typed yet")
        XCTAssertNil(policy.completedSentence(in: "their going to "), "sentence not finished")
        XCTAssertNil(policy.completedSentence(in: "Ok. "), "too short")
        XCTAssertEqual(policy.completedSentence(in: "hi john how are you\n")?.original, "hi john how are you")
    }

    func testLiveCorrectionReconcilesWithTypingSinceCapture() {
        let policy = LiveCorrectionPolicy()
        let doc = SimulatedTextDocument(text: "Hi. their going to the park. ")
        let pending = policy.completedSentence(in: doc.documentContextBeforeInput!)!
        doc.insertText("See y")  // user kept typing while the model ran
        let steps = policy.reconcile(pending, corrected: "They're going to the park.", contextBefore: doc.documentContextBeforeInput!)
        EditPlanner.apply(XCTUnwrap(steps), to: doc)
        XCTAssertEqual(doc.text, "Hi. They're going to the park. See y")
        XCTAssertEqual(doc.cursor, doc.text.count)
    }

    func testLiveCorrectionRefusesWhenSentenceChanged() {
        let policy = LiveCorrectionPolicy()
        let pending = PendingCorrection(original: "their going to the park.", tail: " ")
        XCTAssertNil(policy.reconcile(pending, corrected: "They're going to the park.", contextBefore: "Hi. their going to the zoo. "))
    }
}

private func XCTUnwrap(_ steps: [EditStep]?) -> [EditStep] {
    guard let steps else {
        XCTFail("expected an edit plan")
        return []
    }
    return steps
}
