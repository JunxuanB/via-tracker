import Foundation

/// Shared translations for the app, widgets and Live Activities.
public enum L10n {
  static let resources = Bundle.module
  private static let english = Bundle(path: resources.path(forResource: "en", ofType: "lproj")!)!
  private static let chinese = Bundle(path: resources.path(forResource: "zh-Hans", ofType: "lproj")!)!
  public static var language: String {
    let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
    return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
  }

  public static func eventTitle(estimated: Bool, arrival: Bool) -> String {
    if arrival { return text(estimated ? "预计到达" : "计划到达") }
    return text(estimated ? "预计发车" : "计划发车")
  }

  public static func text(_ key: String, _ arguments: String...) -> String {
    localized(key, language: language, arguments: arguments)
  }

  /// Explicit language selection is also used for deterministic tests.
  public static func localized(_ key: String, language: String, arguments: [String] = []) -> String {
    let language = language.hasPrefix("zh") ? "zh-Hans" : "en"
    let bundle = language == "zh-Hans" ? chinese : english
    let format = bundle.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale(identifier: language), arguments: arguments)
  }
}
