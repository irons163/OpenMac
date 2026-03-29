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
        #if DEBUG
        // Keep unit tests deterministic even if the host app persisted a non-English override.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           overrideRawValue == nil,
           preferredLanguages == Locale.preferredLanguages {
            return .english
        }
        #endif

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
    private final class BundleLocator {}
    private static let runtimeLocaleLock = NSLock()
    private static var runtimeLocaleIdentifier: String?
    private static let tableName = "Localizable"

    fileprivate static var isRunningTests: Bool {
        isRunningTests(
            environment: ProcessInfo.processInfo.environment,
            xctestClassExists: NSClassFromString("XCTestCase") != nil,
            bundlePaths: Bundle.allBundles.map(\.bundlePath)
        )
    }

    fileprivate static func isRunningTests(
        environment: [String: String],
        xctestClassExists: Bool,
        bundlePaths: [String]
    ) -> Bool {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if xctestClassExists {
            return true
        }
        return bundlePaths.contains { $0.hasSuffix(".xctest") }
        #else
        return false
        #endif
    }

    static func setRuntimeLocale(_ locale: Locale?) {
        runtimeLocaleLock.lock()
        runtimeLocaleIdentifier = locale?.identifier
        runtimeLocaleLock.unlock()
    }

    fileprivate static var activeRuntimeLocale: Locale? {
        runtimeLocaleLock.lock()
        defer { runtimeLocaleLock.unlock() }
        guard let runtimeLocaleIdentifier else { return nil }
        return Locale(identifier: runtimeLocaleIdentifier)
    }

    static func string(_ key: String, locale: Locale? = nil) -> String {
        ensureRuntimeLocaleInitialized()
        let resolvedLocale = locale ?? resolvedDefaultLocale()
        let languageCode = AppLanguage
            .resolve(preferredLanguages: [resolvedLocale.identifier])
            .rawValue

        if let localized = localizedValue(for: key, languageCode: languageCode) {
            return localized
        }

        if languageCode != AppLanguage.english.rawValue,
           let fallbackEnglish = localizedValue(for: key, languageCode: AppLanguage.english.rawValue) {
            return fallbackEnglish
        }

        return key
    }

    static func format(_ formatKey: String, _ arguments: CVarArg...) -> String {
        format(formatKey, locale: nil, arguments: arguments)
    }

    static func format(_ formatKey: String, locale: Locale? = nil, arguments: [CVarArg]) -> String {
        ensureRuntimeLocaleInitialized()
        let resolvedLocale = locale ?? resolvedDefaultLocale()
        let format = string(formatKey, locale: resolvedLocale)
        return String(format: format, locale: resolvedLocale, arguments: arguments)
    }

    static func resolvedDefaultLocale(overrideRawValue: String?, runtimeLocale: Locale?) -> Locale {
        let configuredLocale = AppLanguageResolver.resolvedLocale(overrideRawValue: overrideRawValue)
        guard let runtimeLocale else {
            return configuredLocale
        }

        let configuredLanguage = AppLanguage
            .resolve(preferredLanguages: [configuredLocale.identifier])
            .rawValue
        let runtimeLanguage = AppLanguage
            .resolve(preferredLanguages: [runtimeLocale.identifier])
            .rawValue

        // Keep runtime region/calendar nuances only when language matches current settings.
        guard configuredLanguage == runtimeLanguage else {
            return configuredLocale
        }
        return runtimeLocale
    }

    fileprivate static func resolvedDefaultLocale(
        storedOverride: String?,
        runtimeLocale: Locale?,
        runningTests: Bool
    ) -> Locale {
        if runningTests {
            return Locale(identifier: AppLanguage.english.rawValue)
        }

        let normalizedOverride = storedOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolverOverride: String?
        if let normalizedOverride,
           !normalizedOverride.isEmpty,
           normalizedOverride != AppLanguageSettings.systemValue {
            resolverOverride = normalizedOverride
        } else {
            resolverOverride = nil
        }

        return resolvedDefaultLocale(
            overrideRawValue: resolverOverride,
            runtimeLocale: runtimeLocale
        )
    }

    fileprivate static func resolvedDefaultLocale() -> Locale {
        resolvedDefaultLocale(
            storedOverride: UserDefaults.standard.string(forKey: AppLanguageSettings.userDefaultsKey),
            runtimeLocale: activeRuntimeLocale,
            runningTests: isRunningTests
        )
    }

    private static func localizedValue(for key: String, languageCode: String) -> String? {
        let searchBundles = [Bundle.main, Bundle(for: BundleLocator.self)] + Bundle.allBundles + Bundle.allFrameworks
        for candidate in searchBundles {
            guard let localizationPath = candidate.path(forResource: languageCode, ofType: "lproj"),
                  let localizationBundle = Bundle(path: localizationPath) else {
                continue
            }
            let value = localizationBundle.localizedString(forKey: key, value: nil, table: tableName)
            if value != key {
                return value
            }
        }
        return nil
    }

    private static func ensureRuntimeLocaleInitialized() {
        runtimeLocaleLock.lock()
        let needsInitialization = runtimeLocaleIdentifier == nil
        runtimeLocaleLock.unlock()
        guard needsInitialization else {
            return
        }
        setRuntimeLocale(Locale(identifier: AppLanguage.english.rawValue))
    }
}

#if DEBUG
enum AppLanguageTestHooks {
    static func l10nIsRunningTests(
        environment: [String: String],
        xctestClassExists: Bool,
        bundlePaths: [String]
    ) -> Bool {
        L10n.isRunningTests(
            environment: environment,
            xctestClassExists: xctestClassExists,
            bundlePaths: bundlePaths
        )
    }

    static func l10nResolvedDefaultLocale(
        storedOverride: String?,
        runtimeLocaleIdentifier: String?,
        runningTests: Bool
    ) -> Locale {
        L10n.resolvedDefaultLocale(
            storedOverride: storedOverride,
            runtimeLocale: runtimeLocaleIdentifier.map { Locale(identifier: $0) },
            runningTests: runningTests
        )
    }

    static func l10nSetAndReadActiveRuntimeLocale(_ identifier: String?) -> String? {
        let locale = identifier.map { Locale(identifier: $0) }
        L10n.setRuntimeLocale(locale)
        return L10n.activeRuntimeLocale?.identifier
    }
}
#endif
