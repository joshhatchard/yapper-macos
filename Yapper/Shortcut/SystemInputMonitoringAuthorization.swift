import CoreGraphics
import IOKit.hidsystem

/// Input Monitoring via the system TCC "listen event" service.
///
/// Status uses `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` because, unlike
/// `CGPreflightListenEventAccess()`, it distinguishes "not asked yet" from "denied". The request uses
/// `CGRequestListenEventAccess()`, which prompts at most once; after a denial only System Settings can grant it.
@MainActor
final class SystemInputMonitoringAuthorization: InputMonitoringAuthorizing {
    func status() -> PermissionStatus {
        Self.status(for: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
    }

    func request() {
        _ = CGRequestListenEventAccess()
    }

    nonisolated static func status(for access: IOHIDAccessType) -> PermissionStatus {
        switch access {
        case kIOHIDAccessTypeGranted: .authorized
        case kIOHIDAccessTypeDenied: .denied
        default: .notDetermined
        }
    }
}
