import XCTest
@testable import WritingCore

final class KeyboardLayoutTests: XCTestCase {
    func testAutomaticUsesDeviceLanguageAndManualChoiceWins() {
        XCTAssertEqual(KeyboardLayout.automatic.resolved(languages: ["fr-FR", "en-US"]), .azerty)
        XCTAssertEqual(KeyboardLayout.automatic.resolved(languages: ["fr-CA"]), .qwerty)
        XCTAssertEqual(KeyboardLayout.automatic.resolved(languages: ["de-DE"]), .qwertz)
        XCTAssertEqual(KeyboardLayout.automatic.resolved(languages: ["en-US"]), .qwerty)
        XCTAssertEqual(KeyboardLayout.qwerty.resolved(languages: ["fr-FR"]), .qwerty)
    }

    func testEachLayoutHasEveryLetterOnce() {
        for layout in [KeyboardLayout.qwerty, .azerty, .qwertz] {
            let letters = layout.letterRows.joined().filter { $0.isLetter }
            XCTAssertEqual(String(letters.sorted()), "abcdefghijklmnopqrstuvwxyz")
        }
        XCTAssertEqual(KeyboardLayout.azerty.letterRows, ["azertyuiop", "qsdfghjklm", "wxcvbn,"])
        XCTAssertTrue(KeyboardLayout.alternatives(for: "e").contains("é"))
        XCTAssertTrue(KeyboardLayout.alternatives(for: "c").contains("ç"))
    }

    func testFrenchRoutingKeepsEnglishPromptsSeparate() throws {
        let library = try PromptLibrary.bundled()
        XCTAssertEqual(CorrectionLanguage.detect(in: "Je cai pas écrit francai"), .french)
        XCTAssertEqual(CorrectionLanguage.detect(in: "I have two kids and I live in France."), .english)
        XCTAssertEqual(CorrectionLanguage.detect(in: "On Sunday I go to the café."), .english)
        XCTAssertEqual(library.resolvedAction("fix", text: "Je veux écrire"), "fix_french")
        XCTAssertEqual(library.resolvedAction("fix", text: "I has 2 kid"), "fix")
        XCTAssertEqual(library.resolvedAction("professional", text: "Je veux écrire"), "professional")
        let guarder = try OutputGuard(library: library, action: "fix", text: "il a oublier les cle")
        XCTAssertTrue(guarder.evaluate(source: "il a oublier les cle", output: "Il a oublié les clés.").isAccepted)
        XCTAssertFalse(guarder.evaluate(source: "Je cai pas écrit francai", output: "Je ne sais pas parler français.").isAccepted)
    }

}
