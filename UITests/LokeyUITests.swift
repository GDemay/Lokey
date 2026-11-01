import XCTest

final class LokeyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
    }

    private func element(_ id: String, in root: XCUIApplication? = nil) -> XCUIElement {
        (root ?? app).descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openKeyboardCheck() {
        XCTAssertTrue(element("setup.modelReady").waitForExistence(timeout: 10), "Install a model in the App Group before running these tests.")
        let check = element("setup.checkKeyboard")
        if !check.isHittable { app.swipeUp() }
        check.tap()
        XCTAssertTrue(app.textViews["setup.testText"].waitForExistence(timeout: 5))
        app.textViews["setup.testText"].tap()
    }

    private var keyboardProcess: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.gdemay.lokey.keyboard")
    }

    private func key(_ id: String) -> XCUIElement {
        let inApp = element(id)
        return inApp.exists ? inApp : element(id, in: keyboardProcess)
    }

    private func selectLokeyKeyboard() {
        let globe = app.buttons["Next keyboard"]
        for _ in 0..<5 where !key("kb.fix").exists {
            guard globe.waitForExistence(timeout: 3) else { break }
            globe.tap()
        }
        XCTAssertTrue(key("kb.fix").waitForExistence(timeout: 10), "Enable Lokey in Settings and turn off the simulator's hardware keyboard.")
    }

    private func typeOnKeyboard(_ text: String) {
        for character in text {
            key(character == " " ? "kb.space" : "kb.key.\(character)").tap()
        }
    }

    private func tapSettingsRow(_ label: String, in settings: XCUIApplication) throws {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", label)
        func candidate() -> XCUIElement? {
            for query in [settings.cells, settings.buttons, settings.staticTexts] {
                let row = query.matching(predicate).firstMatch
                if row.exists && row.isHittable { return row }
            }
            return nil
        }
        _ = settings.cells.firstMatch.waitForExistence(timeout: 5)
        var found = candidate()
        for _ in 0..<6 where found == nil {
            settings.swipeUp()
            found = candidate()
        }
        try XCTUnwrap(found, "Settings row missing: \(label)").tap()
    }

    func test01_SetupAndSettings() {
        XCTAssertTrue(element("setup.modelReady").waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(element("editor.text").exists)
        XCTAssertFalse(key("kb.fix").exists)
        screenshot("01-keyboard-setup")
        element("setup.models").tap()
        XCTAssertTrue(element("models.row.lfm2.5-1.2b-instruct-q4").waitForExistence(timeout: 5))
        screenshot("02-models")
        app.navigationBars.buttons.firstMatch.tap()
        element("setup.settings").tap()
        XCTAssertTrue(element("settings.autocorrect").waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Use GPU in the app"].exists)
        screenshot("03-keyboard-settings")
    }

    func test02_SettingsShortcut() throws {
        let open = element("setup.openSettings")
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        if !open.isHittable { app.swipeUp() }
        open.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        for _ in 0..<6 where !settings.navigationBars["Settings"].exists {
            let back = settings.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
            if !back.waitForExistence(timeout: 3) { break }
            back.tap()
        }
        XCTAssertTrue(settings.navigationBars["Settings"].waitForExistence(timeout: 5))
        try tapSettingsRow("General", in: settings)
        try tapSettingsRow("Keyboard", in: settings)
        try tapSettingsRow("Keyboards", in: settings)
        let addKeyboard = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Add New Keyboard'")).firstMatch
        XCTAssertTrue(addKeyboard.waitForExistence(timeout: 5))
        screenshot("04-iphone-settings")
    }

    func test03_SystemKeyboardFixesShortGrammar() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        try tapSettingsRow("General", in: settings)
        try tapSettingsRow("Keyboard", in: settings)
        try tapSettingsRow("Keyboards", in: settings)
        let lokey = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Lokey'")).firstMatch
        if !lokey.waitForExistence(timeout: 2) {
            try tapSettingsRow("Add New Keyboard", in: settings)
            try tapSettingsRow("Lokey", in: settings)
        }
        XCTAssertTrue(lokey.waitForExistence(timeout: 3))
        lokey.tap()
        let toggle = settings.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if (toggle.value as? String) == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            for owner in [settings, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
                let allow = owner.alerts.buttons["Allow"]
                if allow.waitForExistence(timeout: 3) { allow.tap(); break }
            }
        }
        XCTAssertEqual(toggle.value as? String, "1")

        app.activate()
        openKeyboardCheck()
        selectLokeyKeyboard()
        typeOnKeyboard("i has ")
        key("kb.layer").tap()
        key("kb.key.2").tap()
        key("kb.layer").tap()
        typeOnKeyboard(" kid")
        let editor = app.textViews["setup.testText"]
        XCTAssertEqual(editor.value as? String, "I has 2 kid")
        key("kb.fix").tap()
        XCTAssertTrue(key("kb.apply").waitForExistence(timeout: 240))
        screenshot("05-system-keyboard-result")
        key("kb.apply").tap()
        let output = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(["I have 2 kids.", "I have two kids.", "I have 2 kids", "I have two kids"].contains(output), output)
        screenshot("06-system-keyboard-applied")
    }

    func test04_SystemKeyboardAutocorrectAndUndo() throws {
        openKeyboardCheck()
        selectLokeyKeyboard()
        typeOnKeyboard("their going to the park")
        key("kb.key..").tap()
        key("kb.space").tap()
        XCTAssertTrue(key("kb.live.text").waitForExistence(timeout: 240))
        let editor = app.textViews["setup.testText"]
        let corrected = try XCTUnwrap(editor.value as? String).replacingOccurrences(of: "\u{2019}", with: "'")
        XCTAssertTrue(corrected.hasPrefix("They're going to the park."), corrected)
        screenshot("07-system-keyboard-live-correction")
        key("kb.live.resolve").tap()
        let undone = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(undone.hasPrefix("Their going to the park."), undone)
        screenshot("08-system-keyboard-undo")
    }
}
