//
//  OpenMacUITestsLaunchTests.swift
//  OpenMacUITests
//
//  Created by Phil on 2026/3/27.
//

import XCTest
import AppKit

final class OpenMacUITestsLaunchTests: XCTestCase {
    private let bundleIdentifier = "com.irons.OpenMac"

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateResidualAppInstances()
    }

    @MainActor
    func testLaunch() throws {
        try requireUITestOptIn()
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }

    private func requireUITestOptIn() throws {
        guard ProcessInfo.processInfo.environment["RUN_UI_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_UI_TESTS=1 to run macOS UI tests.")
        }
    }

    override func tearDownWithError() throws {
        terminateResidualAppInstances()
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
