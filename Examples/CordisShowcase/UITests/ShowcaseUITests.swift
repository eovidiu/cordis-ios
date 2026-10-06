import XCTest

/// Drives the app the way a user would: the dashboard must react to plugin
/// lifecycle changes made from the Tour and Plugins tabs.
final class ShowcaseUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-resetEntries", "YES"]
    app.launch()
  }

  private func openTab(_ name: String) {
    app.tabBars.buttons[name].tap()
  }

  func testTourStepWithdrawsTheClockCardAndTheNextStepRestoresIt() {
    openTab("Dashboard")
    XCTAssertTrue(app.staticTexts["Clock"].waitForExistence(timeout: 10))

    openTab("Tour")
    app.buttons["Run step"].firstMatch.tap()
    openTab("Dashboard")
    XCTAssertTrue(app.staticTexts["Clock"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Greeter"].exists)

    openTab("Tour")
    app.buttons["Run step"].firstMatch.tap()
    openTab("Dashboard")
    XCTAssertTrue(app.staticTexts["Clock"].waitForExistence(timeout: 10))
  }

  func testEditingAConfigReloadsThePlugin() {
    openTab("Plugins")
    app.staticTexts["greeter"].tap()
    let editor = app.textViews.firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    // Put the caret after the last character, then erase backwards.
    editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    let existing = (editor.value as? String) ?? ""
    editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4))
    editor.typeText("{\"name\": \"Ana\"}")
    let apply = app.buttons["Apply config"]
    XCTAssertTrue(apply.isEnabled, "editor text: \(editor.value ?? "nil")")
    apply.tap()

    openTab("Dashboard")
    XCTAssertTrue(app.staticTexts["Hello, Ana 👋"].waitForExistence(timeout: 10))
  }

  func testDisablingAServiceFromThePluginsListSuspendsItsConsumer() {
    openTab("Plugins")
    let counterRow = app.cells.containing(.staticText, identifier: "counter").element(boundBy: 0)
    // iOS 26 exposes a toggle as a switch nested in a switch; the inner one takes the tap.
    let toggle = counterRow.switches.firstMatch
    (toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle).tap()
    XCTAssertTrue(app.cells.containing(.staticText, identifier: "counter-card")
      .staticTexts["waiting for counter"].waitForExistence(timeout: 10))

    openTab("Dashboard")
    XCTAssertTrue(app.staticTexts["Counter"].waitForNonExistence(timeout: 10))
  }
}
