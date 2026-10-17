/// Decides from what the Accessibility API reports whether an element is a field you can paste
/// into. Pure, so the rule is tested without a screen; the app does the asking.
public enum EditableField {
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    /// A text field, text area or combo box whose value can be set. Secure and search fields are
    /// text fields with a subrole, so they count: a password field is a place a clip is pasted.
    public static func isEditable(role: String?, subrole: String?, valueIsSettable: Bool) -> Bool {
        guard let role, textRoles.contains(role) else { return false }
        return valueIsSettable
    }
}
