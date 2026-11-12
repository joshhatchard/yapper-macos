/// Authorization state for a privacy-protected system capability.
enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}
