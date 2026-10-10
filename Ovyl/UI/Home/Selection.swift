import AppKit
import Observation
import SwiftData
import SwiftUI

/// Cards and rows chosen on Home, a folder's page or a search, to move, pin
/// or delete together. Selecting starts with the Select button, ⌘A, or a ⌘-
/// or ⇧-click on a card; while it's on, a click picks a card instead of
/// opening it, and the bar at the foot of the page acts on what's picked.
@Observable @MainActor
final class Selection {
    /// Whether the page is selecting.
    private(set) var isActive = false
    private(set) var ids: Set<UUID> = []
    /// What the page shows, in order, for ⇧-clicks and Select All.
    private(set) var visible: [UUID] = []
    /// The last card clicked, where a ⇧-click's range starts.
    @ObservationIgnored private var anchor: UUID?

    var count: Int { ids.count }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// Whether everything on the page is selected.
    var hasAll: Bool { !visible.isEmpty && visible.allSatisfy(ids.contains) }

    func begin() { isActive = true }

    /// Stops selecting and lets go of what was selected.
    func end() {
        isActive = false
        ids = []
        anchor = nil
    }

    func toggle(_ id: UUID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        anchor = id
        isActive = true
    }

    func selectAll() {
        ids = Set(visible)
        isActive = true
    }

    func deselectAll() {
        ids = []
        anchor = nil
    }

    /// Keeps to what the page shows: a card that leaves the page, filed
    /// away or deleted, is no longer selected.
    func show(_ shown: [UUID]) {
        if visible != shown { visible = shown }
        let set = Set(shown)
        if !ids.isSubset(of: set) { ids.formIntersection(set) }
    }

    /// A click on a card or row, with the keys held: ⌘ adds or takes it
    /// away, ⇧ adds every card from the last one clicked, and either starts
    /// selecting. While selecting, a plain click adds or takes it away.
    /// Returns whether the click selected, so the card doesn't open.
    func click(_ id: UUID, modifiers: NSEvent.ModifierFlags) -> Bool {
        let keys = modifiers.intersection([.command, .shift])
        guard isActive || !keys.isEmpty else { return false }
        if keys.contains(.shift), let anchor, let from = visible.firstIndex(of: anchor), let to = visible.firstIndex(of: id) {
            ids.formUnion(visible[min(from, to)...max(from, to)])
            isActive = true
        } else {
            toggle(id)
        }
        return true
    }

    /// A click with the keys held for the event being handled.
    func click(_ id: UUID) -> Bool {
        click(id, modifiers: NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
    }
}

/// What's selected, split into notes and folders.
struct Selected {
    let noteIDs: [UUID]
    let folders: [Folder]

    @MainActor
    init(_ selection: Selection, folders all: [Folder]) {
        folders = all.filter { selection.contains($0.id) }
        let folderIDs = Set(folders.map(\.id))
        noteIDs = selection.visible.filter { selection.contains($0) && !folderIDs.contains($0) }
    }

    var isEmpty: Bool { noteIDs.isEmpty && folders.isEmpty }

    /// Pinning pins them all unless every one is pinned already.
    var pins: Bool { folders.contains { !$0.isPinned } }
}

/// The round mark that stands in for a card's dots while selecting: an empty
/// ring, or Beam green with a check once the card is selected.
struct SelectMark: View {
    let isSelected: Bool
    /// The ring's color, and the selected mark's edge, so it reads on any card.
    var color: Color = Palette.textSecondary
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Palette.accent : Color.clear)
            Circle()
                .strokeBorder(isSelected ? color.opacity(0.35) : color.opacity(0.6), lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Palette.onAccent)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }
}

/// The bar at the foot of the page while selecting: how many are selected,
/// and what to do with them. Narrow, it keeps just the icons.
struct SelectionBar: View {
    @Environment(Selection.self) private var selection
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    @Query(sort: \Folder.createdAt) private var folders: [Folder]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(titles: true)
            bar(titles: false)
        }
        .padding(.horizontal, 16)
    }

    private func bar(titles: Bool) -> some View {
        let selected = Selected(selection, folders: folders)
        return FloatingBar {
            Text(selection.count == 0 ? "None selected" : "\(selection.count) selected")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(selection.count == 0 ? Palette.textSecondary : Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 12)
                .padding(.trailing, 4)
            SelectionBarButton(
                symbol: selection.hasAll ? "circle.dashed" : "checkmark.circle",
                title: selection.hasAll ? "Deselect All" : "Select All",
                help: selection.hasAll ? "Deselect All" : "Select All (⌘A)",
                showsTitle: titles
            ) {
                withAnimation(.snappy(duration: 0.2)) {
                    if selection.hasAll { selection.deselectAll() } else { selection.selectAll() }
                }
            }
            if !selected.noteIDs.isEmpty {
                Menu {
                    MoveMenuItems(noteIDs: selected.noteIDs, folders: folders)
                } label: {
                    SelectionBarLabel(symbol: "folder", title: "Move to", showsTitle: titles)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Move the selected notes to a folder")
            }
            if !selected.folders.isEmpty {
                SelectionBarButton(
                    symbol: selected.pins ? "pin" : "pin.slash",
                    title: selected.pins ? "Pin" : "Unpin",
                    help: selected.pins ? "Pin to Sidebar" : "Unpin from Sidebar",
                    showsTitle: titles
                ) {
                    SelectionActions.pin(selected, center: center, selection: selection)
                }
            }
            SelectionBarButton(symbol: "trash", title: "Delete", help: "Delete (⌫)", tint: Palette.danger, showsTitle: titles) {
                SelectionActions.delete(selected, navigator: navigator)
            }
            .disabled(selected.isEmpty)
            SelectionBarButton(symbol: "xmark", title: "Done", help: "Stop selecting (esc)", showsTitle: titles) {
                withAnimation(.snappy(duration: 0.2)) { selection.end() }
            }
        }
        .fixedSize()
    }
}

/// An icon and, when there's room, a title, for the selection bar.
private struct SelectionBarLabel: View {
    let symbol: String
    let title: String
    var tint = Palette.textPrimary
    let showsTitle: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
            if showsTitle {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tint)
        .opacity(isEnabled ? 1 : 0.35)
        .padding(.horizontal, showsTitle ? 12 : 9)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(isHovered && isEnabled ? Palette.hover : .clear))
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
    }
}

private struct SelectionBarButton: View {
    let symbol: String
    let title: String
    let help: String
    var tint = Palette.textPrimary
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SelectionBarLabel(symbol: symbol, title: title, tint: tint, showsTitle: showsTitle)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(help)
    }
}

/// The selection's actions in a card's menu, when the card is selected.
struct SelectionMenuItems: View {
    @Environment(Selection.self) private var selection
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    @Query(sort: \Folder.createdAt) private var folders: [Folder]

    var body: some View {
        let selected = Selected(selection, folders: folders)
        if !selected.noteIDs.isEmpty {
            Menu(selected.noteIDs.count == 1 ? "Move Note to" : "Move \(selected.noteIDs.count) Notes to", systemImage: "folder") {
                MoveMenuItems(noteIDs: selected.noteIDs, folders: folders)
            }
        }
        if !selected.folders.isEmpty {
            let what = selected.folders.count == 1 ? "Folder" : "\(selected.folders.count) Folders"
            Button(selected.pins ? "Pin \(what) to Sidebar" : "Unpin \(what) from Sidebar", systemImage: selected.pins ? "pin" : "pin.slash") {
                SelectionActions.pin(selected, center: center, selection: selection)
            }
        }
        Divider()
        Button(selection.hasAll ? "Deselect All" : "Select All", systemImage: "checkmark.circle") {
            if selection.hasAll { selection.deselectAll() } else { selection.selectAll() }
        }
        Button("Done Selecting", systemImage: "xmark") { selection.end() }
        Divider()
        Button(selection.count == 1 ? "Delete…" : "Delete \(selection.count) Items…", systemImage: "trash", role: .destructive) {
            SelectionActions.delete(selected, navigator: navigator)
        }
    }
}

/// The folders to move notes to: none, or any folder.
private struct MoveMenuItems: View {
    @Environment(Selection.self) private var selection
    @Environment(ProcessingCenter.self) private var center
    let noteIDs: [UUID]
    let folders: [Folder]

    var body: some View {
        Button("No Folder") { move(to: nil) }
        if !folders.isEmpty { Divider() }
        ForEach(folders) { folder in
            Button(folder.name) { move(to: folder.id) }
        }
    }

    private func move(to folder: UUID?) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            center.move(noteIDs, to: folder)
            selection.end()
        }
    }
}

/// What the bar and the menus do with the selection.
@MainActor
enum SelectionActions {
    static func pin(_ selected: Selected, center: ProcessingCenter, selection: Selection) {
        let pins = selected.pins
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            for folder in selected.folders { center.setPinned(folder, pins) }
            selection.end()
        }
    }

    /// Asks first; the window deletes once it's confirmed.
    static func delete(_ selected: Selected, navigator: Navigator) {
        navigator.confirmDeleting(notes: selected.noteIDs, folders: selected.folders.map(\.id))
    }
}
