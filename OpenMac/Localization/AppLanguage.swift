import Foundation

enum AppLanguageSettings {
    static let userDefaultsKey = "appLanguageOverride"
    static let systemValue = "system"
}

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    case french = "fr"
    case spanish = "es"
    case japanese = "ja"
    case korean = "ko"

    var locale: Locale { Locale(identifier: rawValue) }

    var displayNameKey: String {
        switch self {
        case .english:
            return "English"
        case .traditionalChinese:
            return "Traditional Chinese"
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .french:
            return "French"
        case .spanish:
            return "Spanish"
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        }
    }

    static func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for preferredLanguage in preferredLanguages {
            if let matched = match(languageIdentifier: preferredLanguage) {
                return matched
            }
        }
        return .english
    }

    private static func match(languageIdentifier: String) -> AppLanguage? {
        let normalized = languageIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("en") { return .english }
        if normalized.hasPrefix("fr") { return .french }
        if normalized.hasPrefix("es") { return .spanish }
        if normalized.hasPrefix("ja") { return .japanese }
        if normalized.hasPrefix("ko") { return .korean }

        if normalized.hasPrefix("zh-hant")
            || normalized.hasPrefix("zh-tw")
            || normalized.hasPrefix("zh-hk")
            || normalized.hasPrefix("zh-mo") {
            return .traditionalChinese
        }

        if normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn")
            || normalized.hasPrefix("zh-sg") {
            return .simplifiedChinese
        }

        if normalized.hasPrefix("zh") {
            return .traditionalChinese
        }

        return nil
    }
}

enum AppLanguagePreference: Equatable {
    case system
    case language(AppLanguage)

    init(rawValue: String?) {
        let normalized = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == AppLanguageSettings.systemValue {
            self = .system
            return
        }
        if let language = AppLanguage(rawValue: normalized) {
            self = .language(language)
            return
        }
        self = .system
    }

    var rawValue: String {
        switch self {
        case .system:
            return AppLanguageSettings.systemValue
        case let .language(language):
            return language.rawValue
        }
    }
}

enum AppLanguageResolver {
    static func resolvedLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages,
        overrideRawValue: String? = nil
    ) -> AppLanguage {
        let resolvedPreference: AppLanguagePreference
        if let overrideRawValue {
            resolvedPreference = AppLanguagePreference(rawValue: overrideRawValue)
        } else {
            resolvedPreference = AppLanguagePreference(
                rawValue: UserDefaults.standard.string(forKey: AppLanguageSettings.userDefaultsKey)
            )
        }

        if case let .language(language) = resolvedPreference {
            return language
        }

        #if DEBUG
        // Keep deterministic message assertions in unit tests when using host locale defaults.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           overrideRawValue == nil,
           preferredLanguages == Locale.preferredLanguages {
            return .english
        }
        #endif

        return AppLanguage.resolve(preferredLanguages: preferredLanguages)
    }

    static func resolvedLocale(
        preferredLanguages: [String] = Locale.preferredLanguages,
        overrideRawValue: String? = nil
    ) -> Locale {
        resolvedLanguage(
            preferredLanguages: preferredLanguages,
            overrideRawValue: overrideRawValue
        ).locale
    }
}

enum L10n {
    static func string(_ key: String, locale: Locale? = nil) -> String {
        let resolvedLocale = locale ?? AppLanguageResolver.resolvedLocale()
        return String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: resolvedLocale
        )
    }

    static func format(_ formatKey: String, _ arguments: CVarArg...) -> String {
        format(formatKey, locale: nil, arguments: arguments)
    }

    static func format(_ formatKey: String, locale: Locale? = nil, arguments: [CVarArg]) -> String {
        let resolvedLocale = locale ?? AppLanguageResolver.resolvedLocale()
        let format = string(formatKey, locale: resolvedLocale)
        return String(format: format, locale: resolvedLocale, arguments: arguments)
    }
}
