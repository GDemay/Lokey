import XCTest

final class LokeyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-home"]
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
        let globe = app.buttons.matching(NSPredicate(format: "label == 'Next keyboard' OR label == 'Clavier suivant'")).firstMatch
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
        let aliases = ["General": "Général", "Keyboard": "Clavier", "Keyboards": "Claviers", "Add New Keyboard": "Ajouter un clavier"]
        let predicate = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", label, aliases[label] ?? label)
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


    func test00_GuidedOnboardingResumesAndFinishes() {
        app.terminate()
        app.launchArguments = ["--uitest", "--uitest-onboarding"]
        app.launch()
        XCTAssertTrue(element("onboarding.start").waitForExistence(timeout: 10))
        screenshot("onboarding-01-welcome")
        element("onboarding.start").tap()
        XCTAssertTrue(element("setup.modelReady").waitForExistence(timeout: 5))
        screenshot("onboarding-02-download")
        element("onboarding.continue").tap()
        XCTAssertTrue(element("setup.openSettings").waitForExistence(timeout: 5))
        screenshot("onboarding-03-enable")
        app.terminate()
        app.launchArguments = ["--uitest"]
        app.launch()
        XCTAssertTrue(element("setup.openSettings").waitForExistence(timeout: 5), "Resume the unfinished setup step")
        element("onboarding.check").tap()
        XCTAssertTrue(app.textViews["setup.testText"].waitForExistence(timeout: 5))
        app.buttons["Hide keyboard"].tap()
        app.swipeUp()
        element("onboarding.finish").tap()
        XCTAssertTrue(element("setup.screen").waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(element("setup.screen").waitForExistence(timeout: 5))
        XCTAssertFalse(element("onboarding.start").exists)
        screenshot("onboarding-04-home")
    }

    func test01_SetupAndSettings() {
        XCTAssertTrue(element("setup.modelReady").waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(element("editor.text").exists)
        XCTAssertFalse(key("kb.fix").exists)
        screenshot("01-keyboard-setup")
        if !element("setup.models").isHittable { app.swipeUp() }
        element("setup.models").tap()
        XCTAssertTrue(element("models.row.lfm2.5-1.2b-instruct-q4").waitForExistence(timeout: 5))
        screenshot("02-models")
        app.navigationBars.buttons.firstMatch.tap()
        if !element("setup.settings").isHittable { app.swipeUp() }
        element("setup.settings").tap()
        XCTAssertTrue(element("settings.autocorrect").waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Use GPU in the app"].exists)
        screenshot("03-keyboard-settings")
    }

    func test02_SettingsShortcut() throws {
        element("setup.resume").tap()
        element("onboarding.start").tap()
        element("onboarding.continue").tap()
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

    private func enableLokey(fullAccess: Bool) throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        for _ in 0..<6 where !settings.navigationBars["Settings"].exists && !settings.navigationBars["Réglages"].exists {
            let back = settings.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
            if !back.waitForExistence(timeout: 2) { break }
            back.tap()
        }
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
        if (toggle.value as? String) != (fullAccess ? "1" : "0") {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            for owner in [settings, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
                let allow = owner.alerts.buttons.matching(NSPredicate(format: "label == 'Allow' OR label == 'Autoriser'")).firstMatch
                if allow.waitForExistence(timeout: 3) { allow.tap(); break }
            }
        }
        XCTAssertEqual(toggle.value as? String, fullAccess ? "1" : "0")
    }

    func test03_SystemKeyboardFixesShortGrammar() throws {
        try enableLokey(fullAccess: true)

        app.activate()
        openKeyboardCheck()
        selectLokeyKeyboard()
        XCTAssertFalse(key("kb.ask").exists)
        XCTAssertTrue(key("kb.enhance").exists)
        XCTAssertTrue(key("kb.translate").exists)
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
        XCTAssertTrue(element("setup.verified").waitForExistence(timeout: 10))
        screenshot("06-system-keyboard-applied")
    }

    func test04_SystemKeyboardAutocorrectAndUndo() throws {
        openKeyboardCheck()
        selectLokeyKeyboard()
        typeOnKeyboard("their going to the park")
        if !key("kb.key..").exists { key("kb.layer").tap() }
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

    func test05_DownloadModelIfNeeded() {
        let models = element("setup.models")
        if !models.isHittable { app.swipeUp() }
        models.tap()
        let download = element("models.download.lfm2.5-1.2b-instruct-q4")
        if download.waitForExistence(timeout: 2) { download.tap() }
        XCTAssertTrue(app.staticTexts["In use"].waitForExistence(timeout: 300))
        screenshot("download-verified")
    }

    func test06_AZERTYLayoutAndAccents() {
        let settings = element("setup.settings")
        if !settings.isHittable { app.swipeUp() }
        settings.tap()
        element("settings.layout").tap()
        app.buttons["AZERTY"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        openKeyboardCheck()
        selectLokeyKeyboard()
        XCTAssertLessThan(key("kb.key.a").frame.minY, key("kb.key.q").frame.minY)
        XCTAssertEqual(key("kb.key.m").frame.minY, key("kb.key.l").frame.minY, accuracy: 2)
        XCTAssertEqual(key("kb.key.w").frame.midX,
                       (key("kb.key.z").frame.midX + key("kb.key.e").frame.midX) / 2, accuracy: 2)
        XCTAssertEqual(key("kb.key.n").frame.midX,
                       (key("kb.key.u").frame.midX + key("kb.key.i").frame.midX) / 2, accuracy: 2)
        XCTAssertEqual(key("kb.key.’").frame.midX,
                       (key("kb.key.i").frame.midX + key("kb.key.o").frame.midX) / 2, accuracy: 2)
        XCTAssertFalse(key("kb.key.,").exists)
        XCTAssertFalse(key("kb.key..").exists)
        key("kb.layer").tap()
        XCTAssertTrue(key("kb.key.,").exists)
        XCTAssertTrue(key("kb.key..").exists)
        XCTAssertTrue(key("kb.key.€").exists)
        screenshot("azerty-numbers")
        key("kb.layer").tap()
        typeOnKeyboard("azerty ")
        let editor = app.textViews["setup.testText"]
        XCTAssertEqual(editor.value as? String, "Azerty ")
        key("kb.key.e").press(forDuration: 1.2)
        let accented = app.buttons["é"].firstMatch
        XCTAssertTrue(accented.waitForExistence(timeout: 5))
        accented.tap()
        XCTAssertEqual(editor.value as? String, "Azerty é")
        screenshot("azerty-keyboard")

        let u = element("kb.key.u", in: keyboardProcess).frame
        let i = element("kb.key.i", in: keyboardProcess).frame
        let b = element("kb.key.b", in: keyboardProcess).frame
        let space = element("kb.space", in: keyboardProcess).frame
        let screenOrigin = app.coordinate(withNormalizedOffset: .zero)
        // Aim into each visible gap on the side closest to the intended key.
        screenOrigin.withOffset(CGVector(dx: (u.midX + i.midX) / 2 - 1.5, dy: u.midY)).tap()
        screenOrigin.withOffset(CGVector(dx: b.midX, dy: (b.midY + space.midY) / 2 - 2)).tap()
        XCTAssertEqual(editor.value as? String, "Azerty éub")
        key("kb.key.’").tap()
        XCTAssertEqual(editor.value as? String, "Azerty éub’")
    }


    func test07_FrenchCorrectionPreservesWritingMeaning() throws {
        openKeyboardCheck()
        selectLokeyKeyboard()
        typeOnKeyboard("je peut pas venir demain")
        let editor = app.textViews["setup.testText"]
        XCTAssertEqual(editor.value as? String, "Je peut pas venir demain")
        key("kb.fix").tap()
        XCTAssertTrue(key("kb.apply").waitForExistence(timeout: 120))
        let proposal = key("kb.result")
        XCTAssertTrue(proposal.waitForExistence(timeout: 5))
        XCTAssertEqual(proposal.label, "Je peux pas venir demain")
        XCTAssertTrue(key("kb.changeLegend").isHittable)
        XCTAssertTrue(proposal.isHittable)
        XCTAssertEqual(editor.value as? String, "Je peut pas venir demain")
        screenshot("french-correction-suggestion")
        key("kb.apply").tap()
        let output = try XCTUnwrap(editor.value as? String)
        XCTAssertEqual(output, "Je peux pas venir demain")
        XCTAssertTrue(element("setup.verified").waitForExistence(timeout: 5))
        screenshot("french-correction-applied")
    }


    func test08_KeyboardMemoryStatus() throws {
        let settings = element("setup.settings")
        if !settings.isHittable { app.swipeUp() }
        settings.tap()
        let peak = element("settings.keyboardPeak")
        for _ in 0..<4 where !peak.isHittable { app.swipeUp() }
        XCTAssertTrue(peak.waitForExistence(timeout: 5))
        screenshot("keyboard-memory-status")
        #if !targetEnvironment(simulator)
        let label = peak.label
        let value = try XCTUnwrap(label.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".,")).inverted).compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }.last)
        XCTAssertLessThan(value, 77, label)
        #endif
    }

    func test09_TypingWithoutFullAccess() throws {
        try enableLokey(fullAccess: false)
        app.activate()
        openKeyboardCheck()
        selectLokeyKeyboard()
        typeOnKeyboard("bonjour")
        XCTAssertEqual(app.textViews["setup.testText"].value as? String, "Bonjour")
        XCTAssertFalse(element("setup.verified").exists)
        screenshot("typing-without-full-access")
        try enableLokey(fullAccess: true)
    }

    func test10_AZERTYCorrectsOneLetterOnSpace() {
        let settings = element("setup.settings")
        if !settings.isHittable { app.swipeUp() }
        settings.tap()
        element("settings.layout").tap()
        app.buttons["AZERTY"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        openKeyboardCheck()
        selectLokeyKeyboard()

        let editor = app.textViews["setup.testText"]
        typeOnKeyboard("bnjour")
        XCTAssertEqual(editor.value as? String, "Bnjour")
        key("kb.space").tap()
        XCTAssertEqual(editor.value as? String, "Bonjour ")
        key("kb.undo").tap()
        XCTAssertEqual(editor.value as? String, "Bnjour ")

        typeOnKeyboard("bonjpur bonjour hello zxzx ")
        XCTAssertEqual(editor.value as? String, "Bnjour bonjour bonjour hello zxzx ")
    }

    func test11_HoldSpaceAndDragMovesCursor() {
        openKeyboardCheck()
        selectLokeyKeyboard()
        typeOnKeyboard("abcd")
        let space = key("kb.space").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        space.press(forDuration: 0.6, thenDragTo: space.withOffset(CGVector(dx: -31, dy: 0)))
        key("kb.key.x").tap()
        XCTAssertEqual(app.textViews["setup.testText"].value as? String, "Abxcd")
    }

    func test12_TranslateFromFixPreview() throws {
        openKeyboardCheck()
        selectLokeyKeyboard()
        typeOnKeyboard("tu peut venir demain ")
        let editor = app.textViews["setup.testText"]
        let source = try XCTUnwrap(editor.value as? String)
        key("kb.fix").tap()
        XCTAssertTrue(key("kb.apply").waitForExistence(timeout: 120))

        key("kb.translate").tap()
        let english = key("kb.action.to_english")
        XCTAssertTrue(english.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, source)

        english.tap()
        XCTAssertTrue(key("kb.apply").waitForExistence(timeout: 120))
        let translation = key("kb.result").label
        XCTAssertTrue(translation.lowercased().contains("tomorrow"), translation)
        let original = key("kb.original")
        XCTAssertTrue(original.isHittable)
        XCTAssertEqual(original.label.trimmingCharacters(in: .whitespacesAndNewlines),
                       source.trimmingCharacters(in: .whitespacesAndNewlines))
        screenshot("translation-original-and-proposal")
        key("kb.apply").tap()
        XCTAssertEqual((editor.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       translation.trimmingCharacters(in: .whitespacesAndNewlines))
    }

}
