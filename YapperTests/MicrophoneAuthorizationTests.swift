import AVFoundation
import Testing

@testable import Yapper

@Suite("Microphone authorization mapping")
struct MicrophoneAuthorizationTests {
    @Test(
        "AVFoundation authorization maps to app permission status",
        arguments: [
            (AVAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
            (.denied, .denied),
            (.restricted, .restricted),
            (.authorized, .authorized),
        ]
    )
    func mapping(system: AVAuthorizationStatus, expected: PermissionStatus) {
        #expect(PermissionStatus(system) == expected)
    }
}
