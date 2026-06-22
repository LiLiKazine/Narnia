import Foundation
import SwiftData

/// The kind of a vault item. Folders are represented polymorphically as a
/// `VaultItem` with `kind == .folder` and a `nil` `relativePath`.
enum ItemKind: String, Codable, CaseIterable, Sendable {
    case folder, photo, video, document, other
}

/// The shared metadata model for the vault, persisted via SwiftData.
///
/// Represents both folders and files. Folders have `kind == .folder` and
/// `relativePath == nil`; files carry a `relativePath` of the form
/// `"files/<uuid>.<ext>"` pointing at their bytes on disk.
@Model
final class VaultItem {
    @Attribute(.unique) var id: UUID
    var parentID: UUID?          // nil == vault root
    var kind: ItemKind
    var name: String             // folder name, or filename for files
    var relativePath: String?    // nil for folders; "files/<uuid>.<ext>" for files
    var createdAt: Date

    init(id: UUID = UUID(), parentID: UUID?, kind: ItemKind,
         name: String, relativePath: String? = nil, createdAt: Date = Date()) {
        self.id = id; self.parentID = parentID; self.kind = kind
        self.name = name; self.relativePath = relativePath; self.createdAt = createdAt
    }
}
