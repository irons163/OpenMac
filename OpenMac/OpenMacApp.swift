//
//  OpenMacApp.swift
//  OpenMac
//
//  Created by Phil on 2026/3/27.
//

import SwiftUI

fileprivate enum OpenMacAppLogic {
    static func appearanceRawValue(for mode: AppAppearanceMode) -> String {
        mode.rawValue
    }

    static func makeAppearanceSelectionAction(
        mode: AppAppearanceMode,
        applyRawValue: @escaping (String) -> Void
    ) -> () -> Void {
        { applyRawValue(appearanceRawValue(for: mode)) }
    }

    static func languageOverrideRawValue(for language: AppLanguage?) -> String {
        language?.rawValue ?? AppLanguageSettings.systemValue
    }

    static func makeLanguageSelectionAction(
        language: AppLanguage?,
        applyRawValue: @escaping (String) -> Void
    ) -> () -> Void {
        { applyRawValue(languageOverrideRawValue(for: language)) }
    }

    static func makeCycleAppearanceAction(
        currentRawValue: @escaping () -> String,
        applyRawValue: @escaping (String) -> Void
    ) -> () -> Void {
        { applyRawValue(cycledAppearanceRawValue(currentRawValue: currentRawValue())) }
    }

    static func isSelectedLanguage(selectedPreference: AppLanguagePreference, language: AppLanguage?) -> Bool {
        switch (selectedPreference, language) {
        case (.system, nil):
            return true
        case let (.language(selectedLanguage), .some(language)):
            return selectedLanguage == language
        default:
            return false
        }
    }

    static func languageLabel(for language: AppLanguage?) -> String {
        guard let language else {
            return L10n.string("System Default")
        }
        return L10n.string(language.displayNameKey)
    }

    static func cycledAppearanceRawValue(currentRawValue: String) -> String {
        AppAppearanceMode.resolve(rawValue: currentRawValue).next().rawValue
    }
}

@main
struct OpenMacApp: App {
    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppAppearanceMode.system.rawValue
    @AppStorage(AppLanguageSettings.userDefaultsKey) private var appLanguageOverrideRawValue = AppLanguageSettings.systemValue

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: .persistentBoard())
                .environment(\.locale, appLocale)
        }
        .commands {
#if DEBUG
            DeliveryPlanReviewCommands()
#endif

            CommandMenu(L10n.string("Appearance")) {
                Button(
                    L10n.string("Cycle Appearance"),
                    action: OpenMacAppLogic.makeCycleAppearanceAction(
                        currentRawValue: readAppearanceModeRawValue,
                        applyRawValue: applyAppearanceModeRawValue
                    )
                )
                .keyboardShortcut("`", modifiers: [.command, .option])

                Divider()

                appearanceCommandButton(for: .system, shortcut: "0")
                appearanceCommandButton(for: .light, shortcut: "l")
                appearanceCommandButton(for: .dark, shortcut: "d")
            }

            CommandMenu(L10n.string("Language")) {
                languageCommandButton(for: nil)

                Divider()

                ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                    languageCommandButton(for: language)
                }
            }
        }

#if DEBUG
        Window(
            L10n.string("Delivery Plan Review"),
            id: DeliveryPlanReviewSceneConfiguration.windowID
        ) {
            DeliveryPlanReviewScene()
                .environment(\.locale, appLocale)
        }
        .defaultSize(width: 1180, height: 780)
#endif
    }

    private var appLocale: Locale {
        let locale = AppLanguageResolver.resolvedLocale(overrideRawValue: appLanguageOverrideRawValue)
        L10n.setRuntimeLocale(locale)
        return locale
    }

    private func appearanceCommandButton(for mode: AppAppearanceMode, shortcut: Character) -> some View {
        Button(action: OpenMacAppLogic.makeAppearanceSelectionAction(mode: mode, applyRawValue: applyAppearanceModeRawValue)) {
            if selectedAppearanceMode == mode {
                Label(mode.title, systemImage: "checkmark")
            } else {
                Text(mode.title)
            }
        }
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: [.command, .option])
    }

    private var selectedAppearanceMode: AppAppearanceMode {
        AppAppearanceMode.resolve(rawValue: appearanceModeRawValue)
    }

    private var selectedLanguagePreference: AppLanguagePreference {
        AppLanguagePreference(rawValue: appLanguageOverrideRawValue)
    }

    private func languageCommandButton(for language: AppLanguage?) -> some View {
        Button(action: OpenMacAppLogic.makeLanguageSelectionAction(language: language, applyRawValue: applyLanguageOverrideRawValue)) {
            if isSelectedLanguage(language) {
                Label(languageLabel(for: language), systemImage: "checkmark")
            } else {
                Text(languageLabel(for: language))
            }
        }
    }

    private func isSelectedLanguage(_ language: AppLanguage?) -> Bool {
        OpenMacAppLogic.isSelectedLanguage(selectedPreference: selectedLanguagePreference, language: language)
    }

    private func languageLabel(for language: AppLanguage?) -> String {
        OpenMacAppLogic.languageLabel(for: language)
    }

    private func cycleAppearanceMode() {
        appearanceModeRawValue = OpenMacAppLogic.cycledAppearanceRawValue(currentRawValue: appearanceModeRawValue)
    }

    private func readAppearanceModeRawValue() -> String {
        appearanceModeRawValue
    }

    private func applyAppearanceModeRawValue(_ rawValue: String) {
        appearanceModeRawValue = rawValue
    }

    private func applyLanguageOverrideRawValue(_ rawValue: String) {
        appLanguageOverrideRawValue = rawValue
    }
}

extension OpenMacApp {
    mutating func testCycleAppearanceMode() {
        cycleAppearanceMode()
    }

    mutating func testApplyAppearanceModeRawValue(_ rawValue: String) {
        applyAppearanceModeRawValue(rawValue)
    }

    mutating func testApplyLanguageOverrideRawValue(_ rawValue: String) {
        applyLanguageOverrideRawValue(rawValue)
    }

    var testAppearanceModeRawValue: String {
        appearanceModeRawValue
    }

    var testLanguageOverrideRawValue: String {
        appLanguageOverrideRawValue
    }

    func testReadAppearanceModeRawValue() -> String {
        readAppearanceModeRawValue()
    }
}

enum OpenMacAppTestHooks {
    static func appearanceSelectionRawValue(initialRawValue: String, mode: AppAppearanceMode) -> String {
        var rawValue = initialRawValue
        let action = OpenMacAppLogic.makeAppearanceSelectionAction(mode: mode) { rawValue = $0 }
        action()
        return rawValue
    }

    static func languageSelectionRawValue(initialRawValue: String, language: AppLanguage?) -> String {
        var rawValue = initialRawValue
        let action = OpenMacAppLogic.makeLanguageSelectionAction(language: language) { rawValue = $0 }
        action()
        return rawValue
    }

    static func isSelectedLanguage(overrideRawValue: String, language: AppLanguage?) -> Bool {
        OpenMacAppLogic.isSelectedLanguage(
            selectedPreference: AppLanguagePreference(rawValue: overrideRawValue),
            language: language
        )
    }

    static func languageLabel(for language: AppLanguage?) -> String {
        OpenMacAppLogic.languageLabel(for: language)
    }

    static func cycledAppearanceRawValue(currentRawValue: String) -> String {
        OpenMacAppLogic.cycledAppearanceRawValue(currentRawValue: currentRawValue)
    }

    static func appearanceRawValue(for mode: AppAppearanceMode) -> String {
        OpenMacAppLogic.appearanceRawValue(for: mode)
    }

    static func languageOverrideRawValue(for language: AppLanguage?) -> String {
        OpenMacAppLogic.languageOverrideRawValue(for: language)
    }

    static func cycleAppearanceActionRawValue(initialRawValue: String) -> String {
        var rawValue = initialRawValue
        let action = OpenMacAppLogic.makeCycleAppearanceAction(
            currentRawValue: { rawValue },
            applyRawValue: { rawValue = $0 }
        )
        action()
        return rawValue
    }

    static func exerciseInternalMutators(
        initialAppearanceRawValue: String,
        initialLanguageRawValue: String,
        appearanceRawValueToApply: String,
        languageRawValueToApply: String
    ) -> (appliedAppearance: String, appliedLanguage: String, cycledAppearance: String) {
        let defaults = UserDefaults.standard
        let appearanceKey = "appearanceMode"
        let languageKey = AppLanguageSettings.userDefaultsKey
        let previousAppearance = defaults.object(forKey: appearanceKey)
        let previousLanguage = defaults.object(forKey: languageKey)
        defer {
            if let previousAppearance {
                defaults.set(previousAppearance, forKey: appearanceKey)
            } else {
                defaults.removeObject(forKey: appearanceKey)
            }

            if let previousLanguage {
                defaults.set(previousLanguage, forKey: languageKey)
            } else {
                defaults.removeObject(forKey: languageKey)
            }
        }

        defaults.set(initialAppearanceRawValue, forKey: appearanceKey)
        defaults.set(initialLanguageRawValue, forKey: languageKey)

        var app = OpenMacApp()
        app.testApplyAppearanceModeRawValue(appearanceRawValueToApply)
        app.testApplyLanguageOverrideRawValue(languageRawValueToApply)
        let appliedAppearance = app.testAppearanceModeRawValue
        let appliedLanguage = app.testLanguageOverrideRawValue
        app.testCycleAppearanceMode()
        let cycledAppearance = app.testAppearanceModeRawValue
        return (appliedAppearance, appliedLanguage, cycledAppearance)
    }

    static func readAppearanceRawValueFromAppStorage(initialAppearanceRawValue: String) -> String {
        let defaults = UserDefaults.standard
        let appearanceKey = "appearanceMode"
        let previousAppearance = defaults.object(forKey: appearanceKey)
        defer {
            if let previousAppearance {
                defaults.set(previousAppearance, forKey: appearanceKey)
            } else {
                defaults.removeObject(forKey: appearanceKey)
            }
        }

        defaults.set(initialAppearanceRawValue, forKey: appearanceKey)
        let app = OpenMacApp()
        return app.testReadAppearanceModeRawValue()
    }
}
