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

  /// Scrolls the current list until `element` can be tapped.
  private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    var swipes = 0
    while !(element.exists && element.isHittable) && swipes < 8 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertTrue(element.isHittable, "\(element) not reachable", file: file, line: line)
  }

  /// Dismisses the error alert if one is shown and returns its text.
  @discardableResult
  private func dismissAlert() -> String? {
    let alert = app.alerts.firstMatch
    guard alert.waitForExistence(timeout: 3) else { return nil }
    let text = alert.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " ")
    alert.buttons.firstMatch.tap()
    return text
  }

  /// Adds every catalog plugin from the Plugins tab, opens its detail,
  /// restarts it when possible and removes it. Each one must leave a visible
  /// trace (row, card, log line or alert) and the app must keep running.
  func testEveryCatalogPluginCanBeAddedRestartedAndRemoved() {
    let plugins = [
      "clock", "clock-card", "greeter", "counter", "counter-card", "network",
      "weather", "flaky", "theme", "theme-card", "audit",
    ]
    openTab("Plugins")
    for plugin in plugins {
      app.navigationBars["Plugins"].buttons["Add plugin"].tap()
      let choice = app.buttons.containing(.staticText, identifier: plugin).firstMatch
      reveal(choice)
      choice.tap()
      let alert = dismissAlert()

      if plugin == "network" {
        // a service has no card: it reports in the Timeline's Logs
        openTab("Timeline")
        app.buttons["Logs"].tap()
        let log = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'network: providing service'")).firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 5), "network logged nothing")
        openTab("Plugins")
      }
      // network is not in the defaults; every other plugin gets a "-2" entry
      let id = plugin == "network" ? "network" : "\(plugin)-2"
      let row = app.staticTexts[id]
      reveal(row)
      row.tap()
      XCTAssertTrue(app.navigationBars[id].waitForExistence(timeout: 5), "detail of \(id)")
      // the state badge is a Label, which XCUITest may expose as any element type
      let badges = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'state '"))
      XCTAssertTrue(badges.firstMatch.waitForExistence(timeout: 5), "\(id) shows no state")
      let failed = badges.matching(NSPredicate(format: "label == 'state failed'")).firstMatch.exists
      if failed { XCTAssertNotNil(alert, "\(id) failed without telling the user") }

      let restart = app.buttons["Restart"]
      reveal(restart)
      if restart.isEnabled {
        restart.tap()
        dismissAlert()
      }
      let remove = app.buttons["Remove entry"]
      reveal(remove)
      remove.tap()
      dismissAlert()
      if app.navigationBars[id].exists { app.navigationBars.buttons["Plugins"].firstMatch.tap() }
      XCTAssertTrue(app.navigationBars["Plugins"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.staticTexts[id].exists, "\(id) still listed after removal")
      XCTAssertEqual(app.state, .runningForeground, "app stopped after \(plugin)")
      app.swipeDown()
      app.swipeDown()
    }
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

  func testAboutCreditsTheCordisTeamCitesThePaperAndLinksTheSwiftPort() {
    openTab("Tour")
    app.navigationBars.buttons["About"].tap()
    let about = app.navigationBars["About"]
    XCTAssertTrue(about.waitForExistence(timeout: 5))

    // SwiftUI exposes a Link as a button and a combined text block as a
    // generic element, so match on labels rather than element types.
    func element(_ predicate: String) -> XCUIElement {
      app.descendants(matching: .any).matching(NSPredicate(format: predicate)).firstMatch
    }
    XCTAssertTrue(element("label == 'cordiverse/cordis on GitHub'").waitForExistence(timeout: 5))
    XCTAssertTrue(element("label CONTAINS 'Shigma'").exists)
    for predicate in [
      "label CONTAINS 'Spatiotemporal Composability' AND label CONTAINS 'Yifan Shi'",
      "label == 'Read the paper on arXiv'",
      "label == 'eovidiu/cordis-ios on GitHub'",
    ] {
      let target = element(predicate)
      var swipes = 0
      while !(target.exists && target.isHittable) && swipes < 4 {
        app.swipeUp()
        swipes += 1
      }
      XCTAssertTrue(target.isHittable, predicate)
    }

    about.buttons["Done"].tap()
    XCTAssertTrue(about.waitForNonExistence(timeout: 5))
  }
}
