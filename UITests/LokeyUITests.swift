import XCTest

/// End-to-end tests on the iOS Simulator with a real on-device model.
/// CI copies the GGUF into the App Group container before running (scripts/ci/ios-e2e.sh).
final class LokeyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitest"]
        app.launch()
    }

    // MARK: Helpers

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String, in root: XCUIApplication? = nil) -> XCUIElement {
        (root ?? app).descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func requireModel() throws {
        app.tabBars.buttons["Write"].tap()
        if element("editor.needsModel").waitForExistence(timeout: 2) {
            throw XCTSkip("No model installed in the simulator's App Group container")
        }
    }

    /// Types with the in-app keyboard by tapping its keys.
    private func typeOnKeyboard(_ text: String) {
        for ch in text {
            switch ch {
            case " ": element("kb.space").tap()
            default: element("kb.key.\(String(ch).lowercased())").tap()
            }
        }
    }

    /// Element value with typographic apostrophes normalized (iOS smart punctuation).
    private func value(_ id: String) -> String {
        (element(id).value as? String ?? "").replacingOccurrences(of: "\u{2019}", with: "'")
    }

    // MARK: Tests

    func test01_ScreensRender() {
        XCTAssertTrue(element("editor.text").waitForExistence(timeout: 10))
        screenshot("01-write")
        app.tabBars.buttons["Keyboard"].tap()
        XCTAssertTrue(element("kb.fix").waitForExistence(timeout: 10))
        screenshot("02-keyboard-preview")
        element("kb.enhance").tap()
        XCTAssertTrue(element("kb.action.professional").waitForExistence(timeout: 5))
        screenshot("03-keyboard-enhance")
        element("kb.back").tap()
        app.tabBars.buttons["Models"].tap()
        XCTAssertTrue(element("models.row.lfm2.5-1.2b-instruct-q4").waitForExistence(timeout: 10))
        screenshot("04-models")
        app.tabBars.buttons["Settings"].tap()
        screenshot("05-settings")
    }

    func test02_EditorFixesTextOnDevice() throws {
        try requireModel()
        let editor = app.textViews["editor.text"]
        editor.tap()
        editor.typeText("i dont know what to do. their going to the park tomorow")
        element("editor.fix").tap()
        let result = element("editor.result")
        XCTAssertTrue(result.waitForExistence(timeout: 240), "no result from the on-device model")
        let output = (result.value as? String ?? "").replacingOccurrences(of: "\u{2019}", with: "'")
        screenshot("06-editor-fix-result")
        XCTAssertTrue(output.hasPrefix("I don't know what to do"), output)
        XCTAssertTrue(output.contains("they're going to the park tomorrow") || output.contains("They're going to the park tomorrow"), output)

        element("editor.replace").tap()
        XCTAssertEqual((editor.value as? String)?.replacingOccurrences(of: "\u{2019}", with: "'"), output)
        screenshot("07-editor-replaced")
    }

    func test03_KeyboardTypesAndFixes() throws {
        try requireModel()
        app.tabBars.buttons["Keyboard"].tap()
        XCTAssertTrue(element("kb.fix").waitForExistence(timeout: 10))
        typeOnKeyboard("i dont know what to do")
        XCTAssertEqual(value("preview.text"), "I dont know what to do", "auto-capitalization should apply")

        element("kb.fix").tap()
        let apply = element("kb.apply")
        XCTAssertTrue(apply.waitForExistence(timeout: 240), "no result panel")
        screenshot("08-keyboard-fix-result")
        apply.tap()
        XCTAssertTrue(value("preview.text").hasPrefix("I don't know what to do"), value("preview.text"))
        screenshot("09-keyboard-fix-applied")
    }

    func test04_AutocorrectsWhileTyping() throws {
        try requireModel()
        app.tabBars.buttons["Keyboard"].tap()
        XCTAssertTrue(element("kb.fix").waitForExistence(timeout: 10))
        element("preview.clear").tap()
        typeOnKeyboard("their going to the park")
        element("kb.key..").tap()
        element("kb.space").tap()

        let notice = element("kb.live.text")
        XCTAssertTrue(notice.waitForExistence(timeout: 240), "no live correction")
        screenshot("10-live-correction")
        XCTAssertTrue(value("preview.text").hasPrefix("They're going to the park."), value("preview.text"))

        element("kb.live.resolve").tap()  // Undo
        XCTAssertTrue(value("preview.text").hasPrefix("Their going to the park."), value("preview.text"))
        screenshot("11-live-correction-undone")
    }

    /// Best effort: enables the real keyboard extension in Settings and uses it in the app.
    /// Settings UI differs across iOS versions, so missing steps skip rather than fail.
    func test05_SystemKeyboardExtension() throws {
        try requireModel()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        func tapCell(_ label: String) throws {
            // Prefix match: iOS labels vary ("Add New Keyboard…" vs "Add New Keyboard...").
            let predicate = NSPredicate(format: "label BEGINSWITH %@", label)
            func candidate() -> XCUIElement? {
                for query in [settings.cells, settings.buttons, settings.staticTexts] {
                    let element = query.matching(predicate).firstMatch
                    if element.exists && element.isHittable { return element }
                }
                return nil
            }
            _ = settings.cells.firstMatch.waitForExistence(timeout: 5)
            var found = candidate()
            for _ in 0..<6 where found == nil {
                settings.swipeUp()
                found = candidate()
            }
            guard let element = found else {
                screenshot("settings-missing-\(label)")
                throw XCTSkip("Settings step not found: \(label)")
            }
            element.tap()
        }
        try tapCell("General")
        try tapCell("Keyboard")
        try tapCell("Keyboards")
        let alreadyAdded = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Lokey'")).firstMatch
        if !alreadyAdded.waitForExistence(timeout: 2) {
            try tapCell("Add New Keyboard")
            try tapCell("Lokey")
        }
        screenshot("12-settings-keyboard-added")
        if alreadyAdded.waitForExistence(timeout: 3) {
            alreadyAdded.tap()
            let toggle = settings.switches.firstMatch
            if toggle.waitForExistence(timeout: 3), (toggle.value as? String) == "0" {
                toggle.tap()
                let allow = settings.alerts.buttons["Allow"]
                if allow.waitForExistence(timeout: 3) { allow.tap() }
            }
            screenshot("13-settings-full-access")
        }

        app.terminate()
        app.launch()
        app.tabBars.buttons["Write"].tap()
        let editor = app.textViews["editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        // The extension's UI is reachable from the host app or through its own bundle identifier.
        let keyboardProcess = XCUIApplication(bundleIdentifier: "com.gdemay.lokey.keyboard")
        func key(_ id: String) -> XCUIElement {
            let inApp = element(id)
            return inApp.exists ? inApp : keyboardProcess.descendants(matching: .any).matching(identifier: id).firstMatch
        }
        let globe = app.buttons["Next keyboard"]
        for _ in 0..<4 where !key("kb.fix").exists {
            guard globe.waitForExistence(timeout: 3) else { break }
            globe.tap()
        }
        guard key("kb.fix").waitForExistence(timeout: 5) else {
            screenshot("14-system-keyboard-not-reachable")
            throw XCTSkip("Could not switch to the Lokey keyboard (hardware keyboard connected?)")
        }
        screenshot("14-system-keyboard")
        for ch in "she have two brothers" {
            key(ch == " " ? "kb.space" : "kb.key.\(ch)").tap()
        }
        key("kb.fix").tap()
        let apply = key("kb.apply")
        XCTAssertTrue(apply.waitForExistence(timeout: 240))
        screenshot("15-system-keyboard-result")
        apply.tap()
        XCTAssertTrue((editor.value as? String ?? "").contains("has two brothers"), editor.value as? String ?? "")
        screenshot("16-system-keyboard-applied")
    }
}
