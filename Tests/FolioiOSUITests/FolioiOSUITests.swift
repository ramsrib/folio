import XCTest

/// End-to-end: the real app in the simulator, driven through the screen. Each
/// test launches with `--ui-testing` (forget the saved vault) and, where it needs
/// notes, `--vault <path>` pointing at a folder the test just wrote — see
/// `TestLaunch` in the app.
final class FolioiOSUITests: XCTestCase {
    private var vaultDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vaultDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vaultDir)
    }

    private func write(_ relative: String, _ text: String) throws {
        let url = vaultDir.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: vaultDir.appendingPathComponent(relative), encoding: .utf8)
    }

    private func launch(withVault: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (withVault ? ["--vault", vaultDir.path] : [])
        app.launch()
        return app
    }

    private func sampleVault() throws {
        try write("Welcome.md", "# Welcome\n\nThis is the first note. #intro\n")
        try write("Projects/Folio.md", "# Folio\n\nA notes app for people who keep files. #folio\n")
        try write("Projects/Ideas.md", "- one\n- two\n")
    }

    // MARK: - Empty state

    func testLaunchesToEmptyStateAndOpensAppearance() {
        let app = launch(withVault: false)
        XCTAssertTrue(el(app, "No vault open").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Vault…"].exists)

        app.buttons["Appearance"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "Paper (warm)").exists, "theme picker is inline")
        app.buttons["Done"].tap()
        XCTAssertTrue(el(app, "No vault open").waitForExistence(timeout: 3))
    }

    // MARK: - Browsing

    func testVaultBrowserShowsTreeAndExpandsFolders() throws {
        try sampleVault()
        let app = launch(withVault: true)

        XCTAssertTrue(app.navigationBars[vaultDir.lastPathComponent].waitForExistence(timeout: 5),
                      "the title is the vault folder's name")
        XCTAssertTrue(el(app, "Welcome").exists)
        XCTAssertTrue(el(app, "Projects").exists)
        XCTAssertFalse(el(app, "Folio").exists, "folders start collapsed")
        XCTAssertFalse(el(app, "Ideas").exists)

        el(app, "Projects").tap()
        XCTAssertTrue(el(app, "Folio").waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "Ideas").exists)

        el(app, "Projects").tap()
        XCTAssertTrue(waitForDisappearance(el(app, "Folio")))
    }

    func testSearchFiltersByNoteName() throws {
        try sampleVault()
        let app = launch(withVault: true)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "Welcome").exists)

        search.tap()
        search.typeText("ide")
        XCTAssertTrue(el(app, "Ideas").waitForExistence(timeout: 3),
                      "search results are flat and reach into folders that aren't expanded")
        XCTAssertTrue(waitForDisappearance(el(app, "Welcome")), "non-matching notes drop out")
        XCTAssertFalse(el(app, "Projects").exists, "folders don't appear in results")
    }

    // MARK: - Reading and editing

    func testOpenNoteRendersReadingModeThenEditsSaveToDisk() throws {
        try sampleVault()
        let app = launch(withVault: true)
        XCTAssertTrue(el(app, "Projects").waitForExistence(timeout: 5))

        el(app, "Projects").tap()
        el(app, "Folio").tap()
        XCTAssertTrue(app.navigationBars["Folio"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, containing: "A notes app for people who keep files")
                        .waitForExistence(timeout: 5), "reading view renders the paragraph")
        XCTAssertFalse(app.textViews.firstMatch.exists, "reading mode has no editor")

        app.buttons["Edit"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue((editor.value as? String ?? "").contains("# Folio"), "editor shows the note's Markdown")

        // Tap below the last line: the caret lands at the end of the document, so
        // the typed text is appended rather than spliced into the heading.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        editor.typeText("\nAdded from the UI test.\n")

        // Back to reading mode: the same toolbar button, now labelled for the other direction.
        app.buttons["Reading mode"].tap()
        XCTAssertTrue(text(app, containing: "Added from the UI test.").waitForExistence(timeout: 3),
                      "the reading view re-renders the edited content")

        let back = app.navigationBars["Folio"].buttons
            .matching(NSPredicate(format: "label != 'Edit' AND label != 'Reading mode'")).firstMatch
        back.tap()                                            // pop → onDisappear → flushSave
        XCTAssertTrue(el(app, "Projects").waitForExistence(timeout: 3))
        XCTAssertTrue(try read("Projects/Folio.md").contains("Added from the UI test."),
                      "the edit reached the file on disk")
        XCTAssertTrue(try read("Projects/Folio.md").hasPrefix("# Folio\n"),
                      "the rest of the note is untouched")
    }

    // MARK: - Tags

    func testTagBrowserOpensNote() throws {
        try sampleVault()
        let app = launch(withVault: true)
        XCTAssertTrue(app.buttons["Browse tags"].waitForExistence(timeout: 5))

        app.buttons["Browse tags"].tap()
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "#folio").exists)
        XCTAssertTrue(el(app, "#intro").exists)

        el(app, "#intro").tap()
        XCTAssertTrue(app.navigationBars["#intro"].waitForExistence(timeout: 3))
        // Scope to what's tappable: the vault browser behind the sheet has a
        // "Welcome" row of its own, and an unscoped query finds that one first.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Welcome'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3))
        let row = try XCTUnwrap(rows.allElementsBoundByIndex.first { $0.isHittable },
                                "the tag's note row should be tappable inside the sheet")
        row.tap()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 5),
                      "picking a note closes the sheet and pushes the note")
        XCTAssertTrue(text(app, containing: "This is the first note").waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    /// Any on-screen element whose label is `label` (or starts with it as one of
    /// several joined parts, e.g. "#intro, 1"). SwiftUI collapses a row's images
    /// and texts into the enclosing button, so the element type isn't predictable.
    private func el(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ","))
            .firstMatch
    }

    /// A rendered block of the reading view containing `text`.
    private func text(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: element)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }
}
