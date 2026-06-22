//
//  VaultGridUITests.swift
//  NarniaUITests
//
//  Smoke coverage for the vault grid: creating a folder via the toolbar makes a
//  matching cell appear. The app launches directly into the grid (no auth gate
//  yet), so no unlock step is needed.
//

import XCTest

final class VaultGridUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateFolderAppearsInGrid() throws {
        let app = XCUIApplication()
        app.launch()

        // A fixed, unique-ish name so an existing cell can't give a false pass.
        let folderName = "UITestFolderA"

        let newFolderButton = app.buttons["newFolderButton"]
        XCTAssertTrue(
            newFolderButton.waitForExistence(timeout: 10),
            "New Folder toolbar button should exist on the grid"
        )
        newFolderButton.tap()

        // The alert hosts exactly one text field. iOS drops the
        // `.accessibilityIdentifier` set on a TextField inside a SwiftUI
        // `.alert`, so reach it through the alert hierarchy instead of by id.
        let alert = app.alerts["New Folder"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 5),
            "New Folder alert should appear"
        )
        let nameField = alert.textFields.firstMatch
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 5),
            "Folder name field should appear in the alert"
        )

        // Clear the default text, then type the test name.
        nameField.tap()
        if let current = nameField.value as? String, !current.isEmpty {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            nameField.typeText(deletes)
        }
        nameField.typeText(folderName)

        alert.buttons["Create"].tap()

        // The new folder cell should appear in the grid (live @Query refresh).
        // Folder cells are NavigationLinks, which surface as buttons in the a11y
        // tree, so query the button carrying the cell's identifier.
        let cell = app.buttons["item-\(folderName)"]
        XCTAssertTrue(
            cell.waitForExistence(timeout: 10),
            "A cell for the created folder should appear in the grid"
        )
    }
}
