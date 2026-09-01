import Foundation

/// Stable machine identity for production accessibility and UI automation.
///
/// Values describe a product role, never display copy or user/content data.
/// They remain valid when labels, titles, filenames, paths, hashes, accounts,
/// credentials, layouts, and locales change.
enum AccessibilityIdentifiers {
    enum Surface {
        static let library = "playstead.surface.library"
        static let sidebar = "playstead.surface.sidebar"
        static let continueShelf = "playstead.surface.shelf.continue"
        static let favoritesShelf = "playstead.surface.shelf.favorites"
        static let collections = "playstead.surface.collections"
        static let collectionDetail = "playstead.surface.collection-detail"
        static let playQueue = "playstead.surface.shelf.play-queue"
        static let recent = "playstead.surface.shelf.recent"
        static let search = "playstead.surface.search"
        static let filter = "playstead.surface.filter"
        static let gameList = "playstead.surface.game-list"
        static let gameCard = "playstead.surface.game-card"
        static let downloads = "playstead.surface.downloads"
        static let quota = "playstead.surface.quota"
        static let storage = "playstead.surface.storage"
        static let reclaim = "playstead.surface.reclaim"
        static let readiness = "playstead.surface.readiness"
        static let adapter = "playstead.surface.adapter"
        static let bios = "playstead.surface.bios"
        static let controllerSettings = "playstead.surface.controller-settings"

        static let all = [
            library, sidebar, continueShelf, favoritesShelf, collections,
            collectionDetail, playQueue, recent, search, filter, gameList,
            gameCard, downloads, quota, storage, reclaim, readiness, adapter,
            bios, controllerSettings
        ]
    }

    enum Control {
        static let done = "playstead.control.done"
        static let cancel = "playstead.control.cancel"
        static let search = "playstead.control.search"
        static let filter = "playstead.control.filter"
        static let moveUp = "playstead.control.move-up"
        static let moveDown = "playstead.control.move-down"
        static let favorite = "playstead.control.favorite"
        static let queue = "playstead.control.queue"
        static let pin = "playstead.control.pin"
        static let download = "playstead.control.download"
        static let openDownloads = "playstead.control.open-downloads"
        static let openStorage = "playstead.control.open-storage"
        static let openAdapter = "playstead.control.open-adapter"

        static let all = [
            done, cancel, search, filter, moveUp, moveDown, favorite, queue,
            pin, download, openDownloads, openStorage, openAdapter
        ]
    }

    /// Finite identities for synthetic rows used by deterministic UI fixtures.
    /// These are deliberately not generated from catalogue IDs or coordinates.
    enum FixtureRow {
        static let alpha = "playstead.fixture-row.alpha"
        static let beta = "playstead.fixture-row.beta"
        static let gamma = "playstead.fixture-row.gamma"

        static let all = [alpha, beta, gamma]
    }

    static let allStaticIdentifiers = Surface.all + Control.all + FixtureRow.all
}
