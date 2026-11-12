import Foundation
import Testing

@testable import Yapper

@Suite("LaunchEnvironment")
struct LaunchEnvironmentTests {
    @Test("this test-hosting process is detected, so the live app does not start here")
    func detectsHostedTests() {
        #expect(LaunchEnvironment.isHostingTests(ProcessInfo.processInfo.environment))
    }

    @Test("a normal launch environment is not a test host")
    func normalLaunch() {
        #expect(!LaunchEnvironment.isHostingTests(["HOME": "/Users/someone", "PATH": "/usr/bin"]))
    }
}
