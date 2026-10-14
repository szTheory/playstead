import SwiftUI

/// Minimal curation projection shared by the live library mapping and
/// curation views. It stays independent of `CatalogueEntry` so curation
/// consumers do not need to know catalogue decoding details.
struct ShelfItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemID: String
    let isUnidentified: Bool
    let statuses: [LibraryStatus]
}
