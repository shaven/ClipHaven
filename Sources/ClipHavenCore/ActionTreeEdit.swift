import Foundation

/// Edits to an action list, addressed by path: the index at each level, outermost first
/// (`[1, 0]` is the first entry of the second top-level folder). Each edit changes the tree in
/// place; those that move an entry return its new path, or nil when the move is not possible.
public enum ActionTreeEdit {
    public static func node(at path: [Int], in tree: [ActionNode]) -> ActionNode? {
        guard let first = path.first, tree.indices.contains(first) else { return nil }
        if path.count == 1 { return tree[first] }
        guard case .folder(let kids) = tree[first].kind else { return nil }
        return node(at: Array(path.dropFirst()), in: kids)
    }

    /// Adds `node` to the folder at `folder` (the top level when `folder` is empty; the end of the top level when it is not a folder).
    public static func insert(_ node: ActionNode, into folder: [Int], at index: Int, in tree: inout [ActionNode]) {
        if folder.isEmpty {
            tree.insert(node, at: min(max(index, 0), tree.count))
            return
        }
        guard let target = self.node(at: folder, in: tree), isFolder(target) else {
            tree.append(node)
            return
        }
        edit(list: folder, in: &tree) { kids in kids.insert(node, at: min(max(index, 0), kids.count)) }
    }

    public static func remove(_ path: [Int], in tree: inout [ActionNode]) {
        guard let last = path.last, node(at: path, in: tree) != nil else { return }
        edit(list: Array(path.dropLast()), in: &tree) { $0.remove(at: last) }
    }

    public static func rename(_ path: [Int], to title: String, in tree: inout [ActionNode]) {
        guard let last = path.last, node(at: path, in: tree) != nil else { return }
        edit(list: Array(path.dropLast()), in: &tree) { $0[last].title = title }
    }

    /// Moves an entry up (`-1`) or down (`1`) within its own list.
    public static func move(_ path: [Int], by step: Int, in tree: inout [ActionNode]) -> [Int]? {
        guard let last = path.last, node(at: path, in: tree) != nil else { return nil }
        let target = last + step
        var moved = false
        edit(list: Array(path.dropLast()), in: &tree) { list in
            guard list.indices.contains(target) else { return }
            list.swapAt(last, target)
            moved = true
        }
        return moved ? Array(path.dropLast()) + [target] : nil
    }

    /// Moves an entry into the folder just above it, at the end.
    public static func indent(_ path: [Int], in tree: inout [ActionNode]) -> [Int]? {
        guard let last = path.last, last > 0, let entry = node(at: path, in: tree) else { return nil }
        let above = Array(path.dropLast()) + [last - 1]
        guard let folder = node(at: above, in: tree), case .folder(let kids) = folder.kind else { return nil }
        remove(path, in: &tree)
        insert(entry, into: above, at: kids.count, in: &tree)
        return above + [kids.count]
    }

    /// Moves an entry out of its folder, to just after that folder.
    public static func outdent(_ path: [Int], in tree: inout [ActionNode]) -> [Int]? {
        guard path.count > 1, let entry = node(at: path, in: tree) else { return nil }
        let folder = Array(path.dropLast())
        remove(path, in: &tree)
        insert(entry, into: Array(folder.dropLast()), at: folder.last! + 1, in: &tree)
        return Array(folder.dropLast()) + [folder.last! + 1]
    }

    private static func isFolder(_ node: ActionNode) -> Bool {
        if case .folder = node.kind { return true }
        return false
    }

    /// Runs `body` on the list at `list` (the top level when empty).
    private static func edit(list: [Int], in tree: inout [ActionNode], _ body: (inout [ActionNode]) -> Void) {
        guard let first = list.first else { body(&tree); return }
        guard tree.indices.contains(first), case .folder(var kids) = tree[first].kind else { return }
        edit(list: Array(list.dropFirst()), in: &kids, body)
        tree[first].kind = .folder(kids)
    }
}
