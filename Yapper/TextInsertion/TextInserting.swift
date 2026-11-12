/// Delivers text to the focused app. Must not read surrounding app text.
/// Real implementation: `AccessibilityTextInserter` over `SystemAccessibility` + `SystemWorkspace`.
@MainActor
protocol TextInserting: AnyObject {
    /// Never prompts.
    func accessibilityStatus() -> PermissionStatus
    /// Shows the system prompt. Call only from an explicit user action.
    func requestAccessibilityPermission()
    func currentTarget() -> InsertionTarget?
    func insert(_ text: String, into target: InsertionTarget) async throws(TextInsertionError)
}
