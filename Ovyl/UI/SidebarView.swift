import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ovylNote = UTType(exportedAs: "com.fulltimestudio.ovyl.note")
}

/// Notes dragged in the window, to drop on a folder: the note dragged, or
/// every selected note when it's one of them.
struct NoteReference: Codable, Transferable {
    let ids: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ovylNote)
    }
}

extension Folder {
    var color: Color { Color(hex: hex) }
}

/// The left sidebar, in the same look as Settings' sidebar: the mark and
/// Ovyl's name, Home and New, then the folders pinned to it, each with its
/// count. Every folder is on Home; pinning one keeps it here too. Settings
/// and the speech model's state sit at the bottom.
struct SidebarView: View {
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    /// A card carried from Home or a folder, which can be dropped on a folder here.
    @Environment(CardDrag.self) private var cardDrag: CardDrag?
    @AppStorage("showSidebar") private var showSidebar = true
    let notes: [Note]
    let folders: [Folder]
    var onNew: () -> Void

    @State private var renameText = ""
    @State private var dropFolderID: UUID?
    @FocusState private var renameFocused: Bool

    /// Both sidebars, this one and Settings', are this wide.
    static let width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: MainWindowStyler.trafficLightsWidth)
                PillGroup {
                    PillButton(symbol: "sidebar.left", help: "Hide the sidebar (⌘.)") { showSidebar = false }
                }
            }
            .padding(.trailing, 12)
            .frame(height: MainWindowStyler.barHeight)
            .background(WindowDragHandle())

            SidebarHeader(title: "Ovyl")
                .padding(.top, 4)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Button { navigator.go(.home) } label: {
                        SidebarRowLabel("Home", symbol: "circle.grid.3x3", count: notes.count, selected: isListShown(.home) || isUnpinnedFolderShown)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    Button(action: onNew) {
                        SidebarRowLabel("New", symbol: "plus.square")
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("New note from a video, audio or pictures (⌘N)")

                    SidebarSectionTitle(title: "Folders") {
                        Button { center.createFolder() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .help("New folder (⇧⌘N)")
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 2)

                    if pinned.isEmpty, cardDrag?.pinsToSidebar != true {
                        Text(folders.isEmpty ? "Make a folder, then drag notes onto it." : "Pin folders from Home to keep them here.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                    }
                    ForEach(pinned) { folderRow($0) }
                    if cardDrag?.pinsToSidebar == true { pinSlot }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            SidebarFooter()
        }
        .frame(width: Self.width)
        .background(Palette.background, ignoresSafeAreaEdges: .top)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardDrag?.sidebarFrame = $0 }
        .onDisappear { cardDrag?.sidebarFrame = .zero }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pinned.map(\.id))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.border).frame(width: 0.5).ignoresSafeArea(edges: .top)
        }
    }

    private var pinned: [Folder] { folders.filter(\.isPinned) }

    /// A folder that isn't pinned is reached from Home, so Home stays
    /// selected while it's open.
    private var isUnpinnedFolderShown: Bool {
        let list = navigator.route.isList ? navigator.route : navigator.listRoute
        guard case .folder(let id) = list else { return false }
        return folders.first { $0.id == id }?.isPinned == false
    }

    /// Where a folder card carried over the sidebar will be pinned.
    private var pinSlot: some View {
        SidebarRowLabel(symbol: "pin.fill", tint: Palette.accent, targeted: true) {
            Text("Pin to Sidebar").foregroundStyle(Palette.textPrimary)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardDrag?.sidebarPinSlot = $0 }
        .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
    }

    /// Whether the sidebar shows `list` as selected: it's the list on screen,
    /// or the list the open note came from.
    private func isListShown(_ list: Route) -> Bool {
        navigator.route.isList ? navigator.route == list : navigator.listRoute == list
    }

    private func folderRow(_ folder: Folder) -> some View {
        let route = Route.folder(folder.id)
        let count = notes.filter { $0.folderID == folder.id }.count
        return SidebarRowLabel(
            symbol: "folder.fill",
            tint: folder.color,
            count: count,
            selected: isListShown(route),
            targeted: dropFolderID == folder.id || cardDrag?.fileTarget == folder.id
        ) {
            if center.folderToRename == folder.id {
                TextField("Folder name", text: $renameText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Palette.textPrimary)
                    .focused($renameFocused)
                    .onSubmit { commitRename(folder) }
                    .onExitCommand { center.folderToRename = nil }
                    .onAppear {
                        renameText = folder.name
                        DispatchQueue.main.async { renameFocused = true }
                    }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused { commitRename(folder) }
                    }
            } else {
                Text(folder.name)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardDrag?.sidebarFolders[folder.id] = $0 }
        .onDisappear { cardDrag?.sidebarFolders[folder.id] = nil }
        .onTapGesture { navigator.go(route) }
        .contextMenu {
            Button("New Note Here…", systemImage: "plus.square") {
                navigator.go(route)
                onNew()
            }
            Button("Rename", systemImage: "pencil") { center.folderToRename = folder.id }
            PinMenuItem(folder: folder)
            Divider()
            Button("Delete Folder and Its Notes…", systemImage: "trash", role: .destructive) {
                navigator.confirmDeleting(folders: [folder.id])
            }
        }
        .dropDestination(for: NoteReference.self) { references, _ in
            center.move(references.flatMap(\.ids), to: folder.id)
            return true
        } isTargeted: { targeted in
            if targeted { dropFolderID = folder.id } else if dropFolderID == folder.id { dropFolderID = nil }
        }
    }

    private func commitRename(_ folder: Folder) {
        guard center.folderToRename == folder.id else { return }
        center.rename(folder, to: renameText)
        center.folderToRename = nil
    }
}

// MARK: - The sidebars' look

/// The mark and a name at the top of a sidebar: Ovyl's in the window,
/// "Settings" in Settings.
struct SidebarHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            OvylMark()
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 16, height: 16)
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, 14)
    }
}

/// A row in either sidebar: an icon, a name and, in the window's sidebar, a
/// count. Selected, it's a green wash with a green icon and the name in
/// bold; a folder's icon keeps its color.
struct SidebarRowLabel<Title: View>: View {
    let symbol: String
    /// The icon's color when it has its own, as a folder's does.
    var tint: Color?
    var count: Int?
    var selected = false
    /// Something is being dragged over the row.
    var targeted = false
    @ViewBuilder var title: Title

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12.5))
                .foregroundStyle(tint ?? (selected ? Palette.accent : Palette.textSecondary))
                .frame(width: 18)
            title
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RowBackground(selected: selected, targeted: targeted))
        .contentShape(Rectangle())
    }
}

extension SidebarRowLabel where Title == Text {
    init(_ title: String, symbol: String, tint: Color? = nil, count: Int? = nil, selected: Bool = false) {
        self.init(symbol: symbol, tint: tint, count: count, selected: selected) { Text(title) }
    }
}

/// A small capital heading over a group of sidebar rows, as Settings heads
/// its cards, with room for a button at the end.
struct SidebarSectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 9)
        .padding(.trailing, 2)
    }
}

/// A row's highlight, as Beam's: a green wash when selected, edged in green
/// while something is dragged over it, and a faint ink wash on hover.
struct RowBackground: View {
    var selected: Bool
    var targeted = false
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected || targeted ? Palette.accentSoft
                : isHovered ? Palette.hover : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(targeted ? Palette.accentEdge : .clear, lineWidth: 1)
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

/// The actions for a note, shared by the list and the note's menu.
struct NoteMenuItems: View {
    @Environment(ProcessingCenter.self) private var center
    @Environment(Navigator.self) private var navigator
    let note: Note
    let folders: [Folder]

    var body: some View {
        Menu("Move to", systemImage: "folder") {
            Button("No Folder") { center.move([note.id], to: nil) }
                .disabled(note.folderID == nil)
            if !folders.isEmpty { Divider() }
            ForEach(folders) { folder in
                Button(folder.name) { center.move([note.id], to: folder.id) }
                    .disabled(note.folderID == folder.id)
            }
        }
        switch note.status {
        case .queued, .processing:
            Button("Stop Processing", systemImage: "stop.circle") { center.stop(note) }
        case .ready, .failed:
            Button("Process Again", systemImage: "arrow.clockwise") { center.enqueue(note) }
        }
        Button("Show in Finder", systemImage: "folder") { note.revealSource() }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) {
            navigator.confirmDeleting(notes: [note.id])
        }
    }
}

extension Note {
    /// Shows the note's video or pictures in Finder.
    func revealSource() {
        let urls = kind == .pictures ? resolvePictures() : resolveSource().map { [$0] } ?? []
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

/// The foot of the sidebar: Settings, as a row like the others, and while
/// the speech model loads, a quiet line saying so, which goes once the model
/// is ready.
struct SidebarFooter: View {
    @Environment(ProcessingCenter.self) private var center

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status {
                HStack(spacing: 6) {
                    if status.isProblem {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.warning)
                    } else {
                        LogoLoader(.preparing)
                            .frame(width: 12, height: 12)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(status.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .help(status.help)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            SettingsLink {
                SidebarRowLabel("Settings", symbol: "gearshape")
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: status?.label)
    }

    private struct Status {
        let label: String
        let help: String
        var isProblem = false
    }

    /// Nothing while the model is idle or ready.
    private var status: Status? {
        switch center.speechPhase {
        case .loading(let firstTime):
            Status(
                label: "Loading speech model",
                help: firstTime ? "The first time takes about a minute." : "This takes a few seconds."
            )
        case .optimizing:
            Status(
                label: "Optimizing speech",
                help: "Videos are transcribed already. When this one-time step finishes, transcription is faster and uses less power."
            )
        case .failed(let message):
            Status(label: "Using Apple Speech", help: message, isProblem: true)
        case .idle, .ready:
            nil
        }
    }
}
