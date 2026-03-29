//
//  OpenMacApp.swift
//  OpenMac
//
//  Created by Phil on 2026/3/27.
//

import SwiftUI

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
            CommandMenu("Appearance") {
                Button("Cycle Appearance") {
                    cycleAppearanceMode()
                }
                .keyboardShortcut("`", modifiers: [.command, .option])

                Divider()

                appearanceCommandButton(for: .system, shortcut: "0")
                appearanceCommandButton(for: .light, shortcut: "l")
                appearanceCommandButton(for: .dark, shortcut: "d")
            }

            CommandMenu("Language") {
                languageCommandButton(for: nil)

                Divider()

                ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                    languageCommandButton(for: language)
                }
            }
        }
    }

    private var appLocale: Locale {
        AppLanguageResolver.resolvedLocale(overrideRawValue: appLanguageOverrideRawValue)
    }

    private func appearanceCommandButton(for mode: AppAppearanceMode, shortcut: Character) -> some View {
        Button {
            appearanceModeRawValue = mode.rawValue
        } label: {
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
        Button {
            appLanguageOverrideRawValue = language?.rawValue ?? AppLanguageSettings.systemValue
        } label: {
            if isSelectedLanguage(language) {
                Label(languageLabel(for: language), systemImage: "checkmark")
            } else {
                Text(languageLabel(for: language))
            }
        }
    }

    private func isSelectedLanguage(_ language: AppLanguage?) -> Bool {
        switch (selectedLanguagePreference, language) {
        case (.system, nil):
            return true
        case let (.language(selectedLanguage), .some(language)):
            return selectedLanguage == language
        default:
            return false
        }
    }

    private func languageLabel(for language: AppLanguage?) -> String {
        guard let language else {
            return L10n.string("System Default")
        }
        return L10n.string(language.displayNameKey)
    }

    private func cycleAppearanceMode() {
        appearanceModeRawValue = selectedAppearanceMode.next().rawValue
    }
}
