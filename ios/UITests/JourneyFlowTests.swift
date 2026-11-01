import XCTest

@MainActor final class JourneyFlowTests: XCTestCase {
  func testProductionPassengerProgressAndEditor() throws {
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "before"
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-selected-environment", "production"]
    app.launch()
    let progress = app.buttons["confirm-passenger-progress"]
    XCTAssertTrue(progress.waitForExistence(timeout: 20))
    XCTAssertEqual(progress.label, "我已出门，前往车站")
    progress.tap()
    XCTAssertEqual(progress.label, "我已到达车站")
    progress.tap()
    XCTAssertFalse(progress.exists)
    app.buttons["管理行程"].tap()
    XCTAssertFalse(app.buttons["更正行程状态"].exists)
    app.buttons["编辑行程"].tap()
    XCTAssertTrue(app.staticTexts["调整行程安排"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "journey-editor"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let edit = app.buttons["调整出门安排"]
    for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
    edit.tap()
    XCTAssertTrue(app.staticTexts["确认发车时间"].waitForExistence(timeout: 5))
    app.buttons["next-planning"].tap()
    app.buttons["增加15分钟"].tap()
    app.buttons["confirm-leg"].tap()
    app.buttons["save-journey"].tap()
    XCTAssertTrue(app.buttons["管理行程"].waitForExistence(timeout: 5))
  }

  func testInstallationOnboardingCanFinishWithoutPermissionsAndPersists() throws {
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "empty"
    app.launchEnvironment["VIA_QA_ONBOARDING_ID"] = UUID().uuidString
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let next = app.buttons["onboarding-next"]
    XCTAssertTrue(next.waitForExistence(timeout: 20))
    XCTAssertTrue(app.staticTexts["独立开发 · 非官方产品"].exists)
    // Scroll on compact screens and at larger text sizes to reach the footer.
    for _ in 0..<8 where !next.isHittable { app.swipeUp() }
    next.tap()
    let finish = app.buttons["onboarding-finish"]
    XCTAssertTrue(finish.waitForExistence(timeout: 5))
    for _ in 0..<8 where !finish.isHittable { app.swipeUp() }
    finish.tap()
    XCTAssertTrue(app.buttons["添加第一趟行程"].waitForExistence(timeout: 10))
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["添加第一趟行程"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["onboarding-next"].exists)
    app.terminate()
    // A fresh installation has a separate completion flag.
    app.launchEnvironment["VIA_QA_ONBOARDING_ID"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.buttons["onboarding-next"].waitForExistence(timeout: 15))
  }

  func testStorageWarmupShowsLoadingScreen() throws {
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "empty"
    app.launchEnvironment["VIA_QA_STORAGE_DELAY_MS"] = "10000"
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let loading = app.staticTexts.matching(
      NSPredicate(format: "label == %@ OR label == %@", "正在载入行程", "正在打开本地数据，请稍候…")
    ).firstMatch
    XCTAssertTrue(loading.waitForExistence(timeout: 4))
    XCTAssertTrue(app.buttons["添加第一趟行程"].waitForExistence(timeout: 15))
  }

  func testCreateAndCorrectJourney() throws {
    let app = XCUIApplication()
    app.launchEnvironment["VIA_QA_SCENARIO"] = "ui-test"
    app.launchEnvironment["VIA_QA_STORE"] = UUID().uuidString
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-selected-environment", "test"]
    app.launch()
    XCTAssertTrue(app.buttons["添加第一趟行程"].waitForExistence(timeout: 20))
    app.buttons["添加第一趟行程"].tap()
    let candidate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'candidate-'"))
      .firstMatch
    XCTAssertTrue(candidate.waitForExistence(timeout: 10))
    candidate.tap()
    app.buttons["下一步"].tap()
    app.buttons["boarding-station"].tap()
    XCTAssertTrue(app.buttons["station-1"].waitForExistence(timeout: 5))
    app.buttons["station-1"].tap()
    app.buttons["next-stations"].tap()
    app.buttons["next-planning"].tap()
    let decrement = app.buttons["减少15分钟"]
    decrement.tap()
    decrement.tap()
    XCTAssertTrue(
      app.otherElements["前往车站 0 分钟"].exists,
      app.debugDescription)
    app.buttons["confirm-leg"].tap()
    XCTAssertTrue(app.buttons["save-journey"].waitForExistence(timeout: 10))
    app.buttons["返回"].tap()
    app.buttons["confirm-leg"].tap()
    app.buttons["save-journey"].tap()
    XCTAssertTrue(app.buttons["管理行程"].waitForExistence(timeout: 10))
    app.buttons["管理行程"].tap()
    app.buttons["更正行程状态"].tap()
    app.buttons["已完成"].tap()
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
    XCTAssertTrue(app.buttons["保持我的出门安排"].waitForExistence(timeout: 15))
    app.buttons["保持我的出门安排"].tap()
    XCTAssertFalse(app.buttons["保持我的出门安排"].exists)
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
    let activity = app.buttons["开启实时活动"]
    for _ in 0..<18 where !activity.isHittable { app.swipeUp() }
    XCTAssertTrue(activity.isHittable, "Maximum accessibility text must keep journey actions reachable")
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
    let trains = app.buttons["列车"]
    guard trains.waitForExistence(timeout: 10) else { throw XCTSkip("iPhone tab bar smoke check") }
    trains.tap()
    let row = app.buttons.matching(
      NSPredicate(format: "label CONTAINS '始发'")
    ).firstMatch
    XCTAssertTrue(
      row.waitForExistence(timeout: 30), "The native app must decode and show the deployed feed")
    let failure = app.staticTexts["暂时无法更新 · 保留最近有效数据"]
    if !failure.waitForNonExistence(timeout: 20) {
      app.buttons["设置"].tap()
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH '数据来源'")).firstMatch.tap()
      XCTFail("The live feed must refresh successfully: \(app.debugDescription)")
      return
    }
    app.buttons["设置"].tap()
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH '数据来源'")).firstMatch.tap()
    XCTAssertTrue(app.buttons["立即刷新"].waitForExistence(timeout: 5))
    app.buttons["立即刷新"].tap()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    formatter.timeZone = TimeZone(identifier: "America/Toronto")
    formatter.dateFormat = "M月d日 HH:mm"
    let recent = (0...2).map { formatter.string(from: Date().addingTimeInterval(-Double($0 * 60))) }
    let fetched = app.staticTexts.matching(
      NSCompoundPredicate(
        orPredicateWithSubpredicates: recent.map {
          NSPredicate(format: "label CONTAINS %@", $0)
        })
    ).firstMatch
    XCTAssertTrue(
      fetched.waitForExistence(timeout: 30),
      "A cached list must not hide failure to fetch current data: \(app.debugDescription)")
    app.buttons["完成"].tap()
    app.buttons["列车"].tap()
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "real-service-feed"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
