import Foundation
import Testing
@testable import TrackerCore

@Test func translationsPreserveValuesAndFallbackToEnglish() {
  #expect(L10n.localized("%@ 天后", language: "en", arguments: ["3"]) == "In 3 days")
  #expect(L10n.localized("%@ 天后", language: "zh-Hans", arguments: ["3"]) == "3 天后")
  #expect(L10n.localized("已到达 %@", language: "en", arguments: ["Montréal"]) == "Arrived at Montréal")
  #expect(L10n.localized("设置", language: "fr") == "Settings")
  #expect(L10n.localized("欢迎搭乘\\nTrain Tracker", language: "en") == "Welcome aboard\nTrain Tracker")
}

@Test func translationCatalogsAreCompleteAndPreservePlaceholders() throws {
  func catalog(_ language: String) throws -> [String: String] {
    let url = try #require(L10n.resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"))
    return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
  }
  let english = try catalog("en"), chinese = try catalog("zh-Hans")
  #expect(english.count >= 439)
  #expect(Set(english.keys) == Set(chinese.keys))
  for (key, value) in english {
    #expect(!value.isEmpty)
    #expect(value.range(of: "\\p{Han}", options: .regularExpression) == nil)
    #expect(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
  }
}
