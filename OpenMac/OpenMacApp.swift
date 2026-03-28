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

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: .persistentBoard())
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
        }
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

    private func cycleAppearanceMode() {
        appearanceModeRawValue = selectedAppearanceMode.next().rawValue
    }
}
