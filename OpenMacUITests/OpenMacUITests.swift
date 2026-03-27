//
//  OpenMacUITests.swift
//  OpenMacUITests
//
//  Created by Phil on 2026/3/27.
//

import XCTest
import AppKit

final class OpenMacUITests: XCTestCase {
    private let bundleIdentifier = "com.irons.OpenMac"
    private var app: XCUIApplication!
    private var didLaunchApp = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateResidualAppInstances()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        didLaunchApp = false
    }

    override func tearDownWithError() throws {
        if didLaunchApp {
            app.terminate()
        }
        app = nil
        didLaunchApp = false
        terminateResidualAppInstances()
    }

    @MainActor
    func testBoardTitleIsVisibleAfterLaunch() throws {
        try requireUITestOptIn()
        app.launch()
        didLaunchApp = true
        XCTAssertTrue(
            app.staticTexts["AI Agent Kanban Dispatch"].waitForExistence(timeout: 5),
            "The board title should be visible after launch."
        )
    }

    private func requireUITestOptIn() throws {
        guard ProcessInfo.processInfo.environment["RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_UI_TESTS=1 to run macOS UI tests.")
        }
    }

    private func terminateResidualAppInstances() {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for runningApp in runningApps {
            if !runningApp.isTerminated {
                runningApp.forceTerminate()
            }
        }
    }
}
