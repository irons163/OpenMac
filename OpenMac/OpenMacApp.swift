//
//  OpenMacApp.swift
//  OpenMac
//
//  Created by Phil on 2026/3/27.
//

import SwiftUI

@main
struct OpenMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: .persistentBoard())
        }
    }
}
