import Foundation
import Observation

/// Where the window is: a list of notes, a note, or a note's media pushed
/// into the middle.
enum Route: Hashable {
    case home
    case folder(UUID)
    case note(UUID)
    /// The frames grabbed from a note's video, or its pictures, in a grid.
    case gallery(UUID)
    /// A note's media in the middle: its video (or first picture) when `item`
    /// is nil, otherwise that frame or picture.
    case media(UUID, item: Int?)

    /// The note this route shows, if any.
    var noteID: UUID? {
        switch self {
        case .note(let id), .gallery(let id), .media(let id, _): id
        case .home, .folder: nil
        }
    }

    var isList: Bool {
        switch self {
        case .home, .folder: true
        default: false
        }
    }
}

/// The window's route with back and forward history, like a browser.
@MainActor @Observable
final class Navigator {
    private(set) var route: Route
    private(set) var back: [Route] = []
    private(set) var forward: [Route] = []
    /// The list a note was opened from, for the sidebar highlight.
    private(set) var listRoute: Route = .home
    /// The notes and folders waiting for the user to confirm their deletion.
    var pendingDeletion: PendingDeletion?
    /// Beside a note, the right pane shows the note's info instead of its media.
    var showsNoteInfo = false
    /// The note's info was opened over its media, so leaving it goes back to
    /// the media; opened into a hidden pane, leaving it closes the pane.
    var noteInfoReturnsToMedia = false

    init(_ route: Route = .home, history: [Route] = [], showsNoteInfo: Bool = false) {
        self.route = route
        back = history
        self.showsNoteInfo = showsNoteInfo
        noteInfoReturnsToMedia = showsNoteInfo
        if route.isList { listRoute = route }
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// Where going back leads.
    var previous: Route? { back.last }

    /// Goes to `next` as a step back when it's where the window just came
    /// from, so returning doesn't pile up history.
    func goBack(to next: Route) {
        if back.last == next { goBack() } else { go(next) }
    }

    func go(_ next: Route) {
        guard next != route else { return }
        back.append(route)
        forward.removeAll()
        set(next)
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(route)
        set(previous)
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(route)
        set(next)
    }

    /// Asks to delete notes and folders; the window confirms first.
    func confirmDeleting(notes: [UUID] = [], folders: [UUID] = []) {
        guard !notes.isEmpty || !folders.isEmpty else { return }
        pendingDeletion = PendingDeletion(notes: notes, folders: folders)
    }

    /// Drops routes to notes and folders that no longer exist.
    func prune(notes: Set<UUID>, folders: Set<UUID>) {
        func valid(_ route: Route) -> Bool {
            if let id = route.noteID { return notes.contains(id) }
            if case .folder(let id) = route { return folders.contains(id) }
            return true
        }
        back = back.filter(valid)
        forward = forward.filter(valid)
        if !valid(listRoute) { listRoute = .home }
        if !valid(route) { set(listRoute) }
    }

    private func set(_ next: Route) {
        route = next
        if next.isList { listRoute = next }
    }
}

/// Notes and folders waiting for the user to confirm their deletion. A
/// folder takes everything in it along.
struct PendingDeletion: Equatable {
    var notes: [UUID] = []
    var folders: [UUID] = []
}

/// What the window asks before deleting: a title, what happens, and the
/// button that does it. Deleting a folder deletes the notes in it, and the
/// question says so.
struct DeletionPrompt: Equatable {
    let title: String
    let message: String
    let button: String

    /// `notes` are the titles of the notes chosen, outside the folders
    /// chosen; `folders` the folders chosen, with how many notes each holds.
    init(notes: [String], folders: [(name: String, notes: Int)]) {
        let inside = folders.reduce(0) { $0 + $1.notes }
        let originals = "The original videos, audio and pictures stay where they are."
        let goesToo = "Deleting a folder deletes everything in it. The notes and their frames are removed from Ovyl; the original videos, audio and pictures stay where they are."
        switch (notes.count, folders.count) {
        case (0, 0):
            // Nothing left to delete, as while the question goes away.
            title = "Delete?"
            message = ""
            button = "Delete"
        case (1, 0):
            title = "Delete “\(notes[0])”?"
            message = "The note and its frames are removed from Ovyl. The original video, audio or pictures stay where they are."
            button = "Delete"
        case (let n, 0):
            title = "Delete \(Self.count(n, "note"))?"
            message = "The notes and their frames are removed from Ovyl. \(originals)"
            button = "Delete \(n) Notes"
        case (0, 1):
            let folder = folders[0]
            if inside == 0 {
                title = "Delete “\(folder.name)”?"
                message = "The folder is empty."
                button = "Delete Folder"
            } else {
                title = "Delete “\(folder.name)” and \(inside == 1 ? "the note" : "the \(inside) notes") in it?"
                message = goesToo
                button = inside == 1 ? "Delete Folder and Note" : "Delete Folder and Notes"
            }
        case (0, let f):
            if inside == 0 {
                title = "Delete \(f) folders?"
                message = "The folders are empty."
                button = "Delete \(f) Folders"
            } else {
                title = "Delete \(f) folders and the \(Self.count(inside, "note")) in them?"
                message = goesToo
                button = "Delete Folders and Notes"
            }
        case (let n, let f):
            let chosen = "\(Self.count(n, "note")) and \(Self.count(f, "folder"))"
            if inside == 0 {
                title = "Delete \(chosen)?"
                message = "The notes and their frames are removed from Ovyl. \(originals)"
            } else {
                title = "Delete \(chosen), with the \(Self.count(inside, "note")) in \(f == 1 ? "it" : "them")?"
                message = goesToo
            }
            button = "Delete All"
        }
    }

    private static func count(_ n: Int, _ word: String) -> String {
        n == 1 ? "1 \(word)" : "\(n) \(word)s"
    }
}
