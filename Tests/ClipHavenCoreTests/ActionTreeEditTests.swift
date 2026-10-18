import XCTest
@testable import ClipHavenCore

final class ActionTreeEditTests: XCTestCase {
    private func s(_ name: String) -> ActionNode { ActionNode(title: name, kind: .script("\(name).js")) }
    private func folder(_ name: String, _ kids: [ActionNode]) -> ActionNode { ActionNode(title: name, kind: .folder(kids)) }
    private func titles(_ tree: [ActionNode]) -> [String] { tree.map(\.title) }

    func testInsertAtTopLevelAndIntoFolder() {
        var tree = [s("A"), folder("F", [s("B")])]
        ActionTreeEdit.insert(s("C"), into: [], at: 1, in: &tree)
        XCTAssertEqual(titles(tree), ["A", "C", "F"])
        ActionTreeEdit.insert(s("D"), into: [2], at: 1, in: &tree)
        XCTAssertEqual(titles(tree), ["A", "C", "F"])
        guard case .folder(let kids) = tree[2].kind else { return XCTFail() }
        XCTAssertEqual(titles(kids), ["B", "D"])
    }

    func testInsertIntoNonFolderAppendsToTop() {
        var tree = [s("A")]
        ActionTreeEdit.insert(s("C"), into: [0], at: 0, in: &tree)
        XCTAssertEqual(titles(tree), ["A", "C"])
    }

    func testRemoveAndRename() {
        var tree = [s("A"), folder("F", [s("B"), s("C")])]
        ActionTreeEdit.remove([1, 0], in: &tree)
        ActionTreeEdit.rename([0], to: "Alpha", in: &tree)
        XCTAssertEqual(titles(tree), ["Alpha", "F"])
        guard case .folder(let kids) = tree[1].kind else { return XCTFail() }
        XCTAssertEqual(titles(kids), ["C"])
    }

    func testMoveUpAndDownStayInsideTheirList() {
        var tree = [s("A"), s("B"), s("C")]
        XCTAssertEqual(ActionTreeEdit.move([1], by: -1, in: &tree), [0])
        XCTAssertEqual(titles(tree), ["B", "A", "C"])
        XCTAssertNil(ActionTreeEdit.move([0], by: -1, in: &tree))
        XCTAssertEqual(ActionTreeEdit.move([1], by: 1, in: &tree), [2])
        XCTAssertNil(ActionTreeEdit.move([2], by: 1, in: &tree))
        XCTAssertEqual(titles(tree), ["B", "C", "A"])
    }

    func testIndentPutsItemInTheFolderAbove() {
        var tree = [folder("F", [s("B")]), s("A")]
        XCTAssertEqual(ActionTreeEdit.indent([1], in: &tree), [0, 1])
        XCTAssertEqual(tree.count, 1)
        guard case .folder(let kids) = tree[0].kind else { return XCTFail() }
        XCTAssertEqual(titles(kids), ["B", "A"])
    }

    func testIndentNeedsAFolderAbove() {
        var tree = [s("X"), s("A")]
        XCTAssertNil(ActionTreeEdit.indent([1], in: &tree))
        XCTAssertNil(ActionTreeEdit.indent([0], in: &tree))
    }

    func testOutdentPutsItemAfterItsFolder() {
        var tree = [folder("F", [s("B"), s("A")]), s("Z")]
        XCTAssertEqual(ActionTreeEdit.outdent([0, 0], in: &tree), [1])
        XCTAssertEqual(titles(tree), ["F", "B", "Z"])
        XCTAssertNil(ActionTreeEdit.outdent([1], in: &tree))
    }

    func testNodeAtPath() {
        let tree = [s("A"), folder("F", [s("B")])]
        XCTAssertEqual(ActionTreeEdit.node(at: [1, 0], in: tree)?.title, "B")
        XCTAssertNil(ActionTreeEdit.node(at: [0, 0], in: tree))
        XCTAssertNil(ActionTreeEdit.node(at: [5], in: tree))
    }
}
