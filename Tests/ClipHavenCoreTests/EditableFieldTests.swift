import XCTest
@testable import ClipHavenCore

final class EditableFieldTests: XCTestCase {
    func testTextControlsAreEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            XCTAssertTrue(EditableField.isEditable(role: role, subrole: nil, valueIsSettable: true), role)
        }
    }

    func testSecureAndSearchFieldsAreEditable() {
        XCTAssertTrue(EditableField.isEditable(role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: true))
        XCTAssertTrue(EditableField.isEditable(role: "AXTextField", subrole: "AXSearchField", valueIsSettable: true))
    }

    func testAReadOnlyTextAreaIsNotEditable() {
        XCTAssertFalse(EditableField.isEditable(role: "AXTextArea", subrole: nil, valueIsSettable: false))
        XCTAssertFalse(EditableField.isEditable(role: "AXTextField", subrole: nil, valueIsSettable: false))
    }

    func testOtherControlsAreNotEditable() {
        for role in ["AXButton", "AXStaticText", "AXMenuItem", "AXWindow", "AXImage", "AXWebArea", "AXGroup", nil] {
            XCTAssertFalse(EditableField.isEditable(role: role, subrole: nil, valueIsSettable: true), role ?? "nil")
        }
    }

    func testAnEditableWebElementWithASettableValueCounts() {
        // Browsers expose editable web content as a text area or text field with a settable value.
        XCTAssertTrue(EditableField.isEditable(role: "AXTextArea", subrole: nil, valueIsSettable: true))
    }
}
