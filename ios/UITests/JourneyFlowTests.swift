import XCTest

@MainActor final class JourneyFlowTests: XCTestCase {
  func testCreateAndCorrectJourney() throws {
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "ui-test"
    app.launchEnvironment["VIA_QA_STORE"] = UUID().uuidString
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.buttons["添加第一趟行程"].waitForExistence(timeout: 20))
    app.buttons["添加第一趟行程"].tap()
    let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'candidate-'"))
      .firstMatch
    XCTAssertTrue(candidate.waitForExistence(timeout: 10))
    candidate.tap()
    app.buttons["boarding-station"].tap()
    XCTAssertTrue(app.buttons["station-1"].waitForExistence(timeout: 5))
    app.buttons["station-1"].tap()
    app.buttons["next-stations"].tap()
    let decrement = app.steppers.firstMatch.buttons.element(boundBy: 0)
    decrement.tap()
    decrement.tap()
    XCTAssertTrue(
      app.steppers.firstMatch.label.contains("前往车站 0 分钟"),
      app.steppers.firstMatch.debugDescription)
    app.buttons["confirm-leg"].tap()
    XCTAssertTrue(app.buttons["save-journey"].waitForExistence(timeout: 10))
    app.buttons["返回"].tap()
    app.buttons["confirm-leg"].tap()
    app.buttons["save-journey"].tap()
    XCTAssertTrue(app.buttons["管理行程"].waitForExistence(timeout: 10))
    app.buttons["管理行程"].tap()
    app.buttons["更正个人阶段"].tap()
    app.buttons["行进中"].tap()
    let arrived = app.buttons["确认已到达"]
    for _ in 0..<8 where !arrived.isHittable { app.swipeUp() }
    XCTAssertTrue(arrived.isHittable)
    arrived.tap()
    app.swipeDown()
    XCTAssertTrue(app.staticTexts["行程已完成"].firstMatch.waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "created-and-completed"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.terminate()
    app.launch()
    XCTAssertTrue(
      app.staticTexts["行程已完成"].firstMatch.waitForExistence(timeout: 15),
      "SwiftData must preserve the journey and manual completion after an offline restart")
  }

  func testFormalScheduleChoicePersistsInView() throws {
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "sync"
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.buttons["保留我的规划"].waitForExistence(timeout: 15))
    app.buttons["保留我的规划"].tap()
    XCTAssertFalse(app.buttons["保留我的规划"].exists)
    XCTAssertTrue(app.buttons["管理行程"].exists)
  }
  func testIPadLandscapeLayout() throws {
    guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout test") }
    XCUIDevice.shared.orientation = .landscapeLeft
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "ipad-detail"
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.staticTexts["当前段 · VIA 44"].waitForExistence(timeout: 15))
    let frame = app.windows.firstMatch.frame
    XCTAssertGreaterThan(frame.width, frame.height)
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "ipad-landscape"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testLargestTextCanReachJourneyControls() throws {
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "large-text"
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.buttons["管理行程"].waitForExistence(timeout: 15))
    let arrived = app.buttons["确认已到达"]
    for _ in 0..<18 where !arrived.isHittable { app.swipeUp() }
    XCTAssertTrue(arrived.isHittable, "Maximum accessibility text must keep journey actions reachable")
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "largest-text-controls"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Deployment smoke check: intentionally uses the real API and the normal local store.
  func testLiveServiceFeed() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let trains = app.tabBars.buttons["列车"]
    guard trains.waitForExistence(timeout: 10) else { throw XCTSkip("iPhone tab bar smoke check") }
    trains.tap()
    let row = app.buttons.matching(
      NSPredicate(format: "label CONTAINS '始发服务日期'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 30), "The native app must decode and show the deployed feed")
    let failure = app.staticTexts["暂时无法更新 · 保留最近有效数据"]
    if !failure.waitForNonExistence(timeout: 20) {
      app.tabBars.buttons["设置"].tap()
      app.swipeUp()
      XCTFail("The live feed must refresh successfully: \(app.debugDescription)")
      return
    }
    app.tabBars.buttons["设置"].tap()
    app.swipeUp()
    XCTAssertTrue(app.buttons["立即刷新"].waitForExistence(timeout: 5))
    app.buttons["立即刷新"].tap()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    formatter.timeZone = TimeZone(identifier: "America/Toronto")
    formatter.dateFormat = "M月d日 HH:mm"
    let recent = (0...2).map { formatter.string(from: Date().addingTimeInterval(-Double($0 * 60))) }
    let fetched = app.staticTexts.matching(
      NSCompoundPredicate(orPredicateWithSubpredicates: recent.map {
        NSPredicate(format: "label CONTAINS %@", $0)
      })
    ).firstMatch
    XCTAssertTrue(fetched.waitForExistence(timeout: 30), "A cached list must not hide failure to fetch current data: \(app.debugDescription)")
    app.tabBars.buttons["列车"].tap()
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "real-service-feed"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
