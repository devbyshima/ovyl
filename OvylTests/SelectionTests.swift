import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Ovyl

/// Deleting a folder with what's in it, what the window says before it
/// does, and selecting cards and rows to act on together.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct SelectionTests {
    static let folder = FileManager.default.temporaryDirectory.appending(path: "ovyl-selection")

    private static func center() throws -> ProcessingCenter {
        let container = try ModelContainer(for: Note.self, Folder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ProcessingCenter(container: container)
    }

    private static func allNotes(_ center: ProcessingCenter) -> [Note] {
        (try? center.context.fetch(FetchDescriptor<Note>())) ?? []
    }

    private static func allFolders(_ center: ProcessingCenter) -> [Folder] {
        (try? center.context.fetch(FetchDescriptor<Folder>())) ?? []
    }

    // MARK: Deleting folders

    @Test func deletingAFolderDeletesItsNotes() throws {
        let center = try Self.center()
        let work = center.createFolder(named: "Work")
        let home = center.createFolder(named: "Home")
        let inside = (0..<3).map { center.createTextNote(title: "Work \($0)", markdown: "Text.", in: work.id) }
        let elsewhere = center.createTextNote(title: "Groceries", markdown: "Milk.", in: home.id)
        let loose = center.createTextNote(title: "Loose", markdown: "Text.")
        try FileManager.default.createDirectory(at: inside[0].thumbnailsFolder, withIntermediateDirectories: true)
        OrderStore.save(inside.map(\.id), for: work.id.uuidString)

        center.delete(work)

        let left = Set(Self.allNotes(center).map(\.id))
        #expect(left == [elsewhere.id, loose.id])
        #expect(Self.allFolders(center).map(\.id) == [home.id])
        #expect(!FileManager.default.fileExists(atPath: inside[0].thumbnailsFolder.path))
        #expect(OrderStore.load(work.id.uuidString).isEmpty)
    }

    @Test func deletingNotesAndFoldersTogether() throws {
        let center = try Self.center()
        let work = center.createFolder(named: "Work")
        let trips = center.createFolder(named: "Trips")
        let filed = center.createTextNote(title: "Plan", markdown: "Text.", in: work.id)
        let kept = center.createTextNote(title: "Kyoto", markdown: "Text.", in: trips.id)
        let loose = center.createTextNote(title: "Loose", markdown: "Text.")
        let other = center.createTextNote(title: "Other", markdown: "Text.")

        // A note listed on its own and inside a folder being deleted goes once.
        center.delete(notes: [loose, filed], folders: [work])

        #expect(Set(Self.allNotes(center).map(\.id)) == [kept.id, other.id])
        #expect(Self.allFolders(center).map(\.id) == [trips.id])
    }

    // MARK: What the window asks

    @Test func promptsSayAFolderTakesItsNotes() {
        let note = DeletionPrompt(notes: ["Standup"], folders: [])
        #expect(note.title == "Delete “Standup”?")
        #expect(note.button == "Delete")

        let notes = DeletionPrompt(notes: ["A", "B", "C"], folders: [])
        #expect(notes.title == "Delete 3 notes?")
        #expect(notes.button == "Delete 3 Notes")

        let folder = DeletionPrompt(notes: [], folders: [("Work", 12)])
        #expect(folder.title == "Delete “Work” and the 12 notes in it?")
        #expect(folder.message.hasPrefix("Deleting a folder deletes everything in it."))
        #expect(folder.button == "Delete Folder and Notes")

        let one = DeletionPrompt(notes: [], folders: [("Work", 1)])
        #expect(one.title == "Delete “Work” and the note in it?")
        #expect(one.button == "Delete Folder and Note")

        let empty = DeletionPrompt(notes: [], folders: [("Ideas", 0)])
        #expect(empty.title == "Delete “Ideas”?")
        #expect(empty.message == "The folder is empty.")
        #expect(empty.button == "Delete Folder")

        let folders = DeletionPrompt(notes: [], folders: [("Work", 4), ("Trips", 2)])
        #expect(folders.title == "Delete 2 folders and the 6 notes in them?")
        #expect(folders.message.hasPrefix("Deleting a folder deletes everything in it."))

        let mixed = DeletionPrompt(notes: ["A", "B"], folders: [("Work", 5)])
        #expect(mixed.title == "Delete 2 notes and 1 folder, with the 5 notes in it?")
        #expect(mixed.button == "Delete All")

        // No em dashes in anything the app says.
        for prompt in [note, notes, folder, one, empty, folders, mixed] {
            #expect(!(prompt.title + prompt.message + prompt.button).contains("—"))
        }
    }

    // MARK: Selecting

    @Test func clicksSelectWithKeysOrWhileSelecting() {
        let ids = (0..<5).map { _ in UUID() }
        let selection = Selection()
        selection.show(ids)

        // A plain click opens; ⌘ starts selecting.
        #expect(!selection.click(ids[0], modifiers: []))
        #expect(!selection.isActive)
        #expect(selection.click(ids[1], modifiers: .command))
        #expect(selection.isActive)
        #expect(selection.ids == [ids[1]])

        // ⇧ adds every card from the last one clicked.
        #expect(selection.click(ids[3], modifiers: .shift))
        #expect(selection.ids == Set(ids[1...3]))

        // While selecting, a plain click takes a card away or adds it.
        #expect(selection.click(ids[2], modifiers: []))
        #expect(selection.ids == [ids[1], ids[3]])
        #expect(selection.click(ids[4], modifiers: []))
        #expect(selection.ids == [ids[1], ids[3], ids[4]])

        // Cards that leave the page are no longer selected.
        selection.show(Array(ids.prefix(4)))
        #expect(selection.ids == [ids[1], ids[3]])

        selection.selectAll()
        #expect(selection.hasAll)
        selection.deselectAll()
        #expect(selection.ids.isEmpty)
        #expect(selection.isActive)
        selection.end()
        #expect(!selection.isActive)
        #expect(!selection.click(ids[0], modifiers: []))
    }

    @Test func selectedSplitsNotesAndFolders() throws {
        let center = try Self.center()
        let work = center.createFolder(named: "Work")
        let trips = center.createFolder(named: "Trips")
        trips.isPinned = false
        let note = center.createTextNote(title: "Plan", markdown: "Text.")
        let selection = Selection()
        selection.show([work.id, note.id, trips.id])
        selection.selectAll()
        let selected = Selected(selection, folders: [work, trips])
        #expect(selected.noteIDs == [note.id])
        #expect(Set(selected.folders.map(\.id)) == [work.id, trips.id])
        // Work is pinned (made from the sidebar) and Trips isn't, so Pin pins both.
        #expect(selected.pins)
    }

    /// Real clicks through a window: a plain click opens a card until
    /// selecting starts, then picks cards, and deleting what's picked asks
    /// first and says the folder's notes go too.
    @Test func clickingCardsWhileSelecting() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let keys = [HomeView.layoutKey, HomeView.sortKey, HomeView.ascendingKey, HomeView.foldersFirstKey, HomeView.showsTextKey, "homeCardScale", "order.home"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        keys.forEach(defaults.removeObject(forKey:))
        defaults.set(1.0, forKey: "homeCardScale")

        let center = try Self.center()
        func note(_ title: String, age: TimeInterval, in folder: UUID? = nil) -> Note {
            let note = center.createTextNote(title: title, markdown: " ", in: folder)
            note.editedMarkdown = ""
            note.createdAt = .now.addingTimeInterval(-age)
            return note
        }
        let first = note("First", age: 1_000)
        let shelf = Folder(name: "Shelf", colorName: "#2A9D8F")
        shelf.createdAt = .now.addingTimeInterval(-2_000)
        center.context.insert(shelf)
        let filed = note("Filed", age: 9_000, in: shelf.id)
        let second = note("Second", age: 3_000)
        center.save()

        let navigator = Navigator(.home)
        let selection = Selection()
        let size = CGSize(width: 1000, height: 640)
        let notes = [first, second, filed]
        let hosting = NSHostingView(rootView:
            CardGrid(folders: [shelf], notes: [first, second], allNotes: notes, allFolders: [shelf])
                .overlay(alignment: .bottom) { if selection.isActive { SelectionBar().padding(.bottom, 16) } }
                .environment(selection)
                .environment(center)
                .environment(navigator)
                .modelContainer(center.container)
                .frame(width: size.width, height: size.height)
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(1))

        func click(_ point: CGPoint) async throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: size.height - point.y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
                if let event { window.sendEvent(event) }
            }
            try await Task.sleep(for: .milliseconds(400))
        }
        func capture(_ name: String) throws {
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: Self.folder.appending(path: "\(name).png"))
            print("SNAPSHOT \(name) \(data.base64EncodedString())")
        }

        // Newest first in three columns: First, Shelf, Second.
        #expect(selection.visible == [first.id, shelf.id, second.id])
        let firstSpot = CGPoint(x: 180, y: 60)
        let shelfSpot = CGPoint(x: 499, y: 60)

        // Selecting: a click picks the card and doesn't open it.
        selection.begin()
        try await Task.sleep(for: .milliseconds(400))
        try await click(firstSpot)
        try await click(shelfSpot)
        #expect(selection.ids == [first.id, shelf.id])
        #expect(navigator.route == .home)
        try capture("selecting")

        // Clicking a picked card again lets it go.
        try await click(firstSpot)
        #expect(selection.ids == [shelf.id])

        // Delete asks first, with the folder's notes counted.
        SelectionActions.delete(Selected(selection, folders: [shelf]), navigator: navigator)
        #expect(navigator.pendingDeletion == PendingDeletion(notes: [], folders: [shelf.id]))
        let prompt = DeletionPrompt(notes: [], folders: [(shelf.name, center.notes(in: shelf).count)])
        #expect(prompt.title == "Delete “Shelf” and the note in it?")

        // Done stops selecting, and a click opens again.
        selection.end()
        try await Task.sleep(for: .milliseconds(400))
        try await click(firstSpot)
        #expect(navigator.route == .note(first.id))

        window.orderOut(nil)
        window.contentView = nil
    }

    /// Home and its list while selecting, light and dark, and a narrow page
    /// where the bar keeps just its icons, for checking by eye.
    @Test func renderSelecting() async throws {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let keys = [HomeView.layoutKey, HomeView.sortKey, HomeView.ascendingKey, HomeView.foldersFirstKey, HomeView.showsTextKey, "homeCardScale", "order.home"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        keys.forEach(defaults.removeObject(forKey:))
        defaults.set(1.0, forKey: "homeCardScale")

        let center = try Self.center()
        let folders = [("Work", "#E2725B", 4), ("Trips", "#B0C246", 2), ("Ideas", "#F1F2EC", 0)].enumerated().map { index, spec in
            let folder = Folder(name: spec.0, colorName: spec.1)
            folder.createdAt = .now.addingTimeInterval(Double(-index) * 30_000 - 5_000)
            center.context.insert(folder)
            for number in 0..<spec.2 {
                center.createTextNote(title: "\(spec.0) \(number)", markdown: "Text.", in: folder.id).createdAt = folder.createdAt
            }
            return folder
        }
        let loose = ["Standup", "Lecture 4", "Groceries", "Reading list"].enumerated().map { index, title in
            let note = center.createTextNote(title: title, markdown: "Some text to show on the card, a line or two of it.")
            note.createdAt = .now.addingTimeInterval(Double(-index) * 20_000)
            return note
        }
        center.save()
        let notes = Self.allNotes(center).sorted { $0.createdAt > $1.createdAt }

        func page(_ selection: Selection) -> some View {
            NotesListView(title: "Home", notes: notes, folders: folders, onNew: {})
                .environment(selection)
                .environment(Navigator(.home))
        }

        let selection = Selection()
        selection.begin()
        let picks = [loose[0].id, folders[0].id, loose[2].id, folders[1].id]
        // The page tells the selection what it shows once it's drawn.
        func pick() { for id in picks where !selection.contains(id) { selection.toggle(id) } }

        for (name, layout, dark, width) in [
            ("selecting-grid", HomeLayout.messy, false, 1100.0),
            ("selecting-grid-dark", .messy, true, 1100),
            ("selecting-list", .list, false, 1100),
            ("selecting-narrow", .messy, false, 520),
        ] {
            defaults.set(layout.rawValue, forKey: HomeView.layoutKey)
            try await render(page(selection), center: center, name: name, dark: dark, size: CGSize(width: width, height: 760), before: pick)
        }
        print("SELECTION SNAPSHOTS \(Self.folder.path)")
    }

    private func render(_ view: some View, center: ProcessingCenter, name: String, dark: Bool, size: CGSize, before: () -> Void) async throws {
        let root = view
            .environment(center)
            .modelContainer(center.container)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(0.6))
        before()
        try await Task.sleep(for: .seconds(0.9))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: Self.folder.appending(path: "\(name).png"))
        print("SNAPSHOT \(name) \(data.base64EncodedString())")
        window.orderOut(nil)
        window.contentView = nil
    }
}
