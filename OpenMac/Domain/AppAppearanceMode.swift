import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return L10n.string("System")
        case .light:
            return L10n.string("Light")
        case .dark:
            return L10n.string("Dark")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func resolve(rawValue: String) -> AppAppearanceMode {
        AppAppearanceMode(rawValue: rawValue) ?? .system
    }

    func next() -> AppAppearanceMode {
        switch self {
        case .system:
            return .light
        case .light:
            return .dark
        case .dark:
            return .system
        }
    }
}

enum AppearanceSchemeResolver {
    static func resolve(systemScheme: ColorScheme, appearanceMode: AppAppearanceMode) -> ColorScheme {
        appearanceMode.preferredColorScheme ?? systemScheme
    }
}
