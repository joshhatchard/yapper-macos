import IOKit.hidsystem
import Testing

@testable import Yapper

@Suite("SystemInputMonitoringAuthorization")
struct InputMonitoringAuthorizationTests {
    @Test(
        "IOHID listen-event access maps to permission status",
        arguments: [
            (kIOHIDAccessTypeGranted, PermissionStatus.authorized),
            (kIOHIDAccessTypeDenied, .denied),
            (kIOHIDAccessTypeUnknown, .notDetermined),
        ])
    func mapsAccessType(access: IOHIDAccessType, expected: PermissionStatus) {
        #expect(SystemInputMonitoringAuthorization.status(for: access) == expected)
    }
}
