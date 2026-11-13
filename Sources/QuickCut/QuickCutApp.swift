import AVKit
import SwiftUI

@main
struct QuickCutApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var editor = Editor()

    var body: some Scene {
        Window("QuickCut", id: "main") {
            ContentView().environment(editor)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { editor.showOpen = true }.keyboardShortcut("o")
                Button("Save Video") { if let t = editor.take { Task { await editor.save(t) } } }
                    .keyboardShortcut("s")
                    .disabled(editor.take == nil || editor.exporting)
            }
            CommandMenu("Timeline") {
                // Disabled while renaming so typing in the field doesn't trigger them.
                let busy = editor.take == nil || editor.renaming != nil
                Button(editor.isPlaying ? "Pause" : "Play") { editor.togglePlay() }
                    .keyboardShortcut(.space, modifiers: []).disabled(busy)
                Button("Cut at Playhead") { editor.cut() }
                    .keyboardShortcut("b").disabled(busy)
                Button("Delete Selected Segments") { editor.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: []).disabled(busy || editor.selection.isEmpty)
            }
        }
    }
}

/// Needed so a bare SwiftPM executable shows up as a regular foreground app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @Environment(Editor.self) private var editor
    @State private var newName = ""

    var body: some View {
        @Bindable var editor = editor
        NavigationSplitView {
            List(editor.takes, selection: $editor.selectedTakeID) { take in
                Label(take.name, systemImage: "film")
                    .tag(take.id)
                    .contextMenu {
                        Button("Rename…") { editor.renaming = .take(take.id) }
                        Button("Save Video") { Task { await editor.save(take) } }.disabled(editor.exporting)
                    }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                Button("Open", systemImage: "plus") { editor.showOpen = true }
            }
        } detail: {
            if editor.take != nil {
                EditorView()
            } else {
                ContentUnavailableView("No Video", systemImage: "film",
                                       description: Text("Press ⌘O to open one or more videos."))
            }
        }
        .navigationTitle(editor.take?.name ?? "QuickCut")
        .frame(minWidth: 800, minHeight: 500)
        .onChange(of: editor.selectedTakeID) {
            editor.selection = []
            editor.currentTime = 0
            editor.reload()
        }
        .fileImporter(isPresented: $editor.showOpen, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            Task { await editor.open((try? result.get()) ?? []) }
        }
        .alert("Rename", isPresented: Binding(get: { editor.renaming != nil }, set: { if !$0 { editor.renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let t = editor.renaming { editor.rename(t, to: newName) } }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: editor.renaming) { if let t = editor.renaming { newName = editor.currentName(of: t) } }
        .alert("Error", isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })) {
            Button("OK") {}
        } message: { Text(editor.error ?? "") }
        .overlay {
            if editor.exporting {
                ProgressView("Saving video…").padding().background(.regularMaterial, in: .rect(cornerRadius: 10))
            }
        }
    }
}

struct EditorView: View {
    @Environment(Editor.self) private var editor

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(player: editor.player)
                .background(.black)
                .contextMenu { saveButton }
            HStack {
                Button(editor.isPlaying ? "Pause" : "Play", systemImage: editor.isPlaying ? "pause.fill" : "play.fill") {
                    editor.togglePlay()
                }
                Text("\(format(editor.currentTime)) / \(format(editor.take?.segments.duration ?? 0))")
                    .monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Cut", systemImage: "scissors") { editor.cut() }.help("Cut at playhead (⌘B)")
                Button("Delete", systemImage: "trash") { editor.deleteSelection() }
                    .help("Delete selected segments (⌫)").disabled(editor.selection.isEmpty)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal).padding(.vertical, 8)
            TimelineStrip()
                .padding([.horizontal, .bottom])
        }
    }

    private var saveButton: some View {
        Button("Save Video") { if let t = editor.take { Task { await editor.save(t) } } }.disabled(editor.exporting)
    }
}

struct TimelineStrip: View {
    @Environment(Editor.self) private var editor

    var body: some View {
        if let take = editor.take {
            let segments = take.segments
            let total = max(segments.duration, 0.001)
            GeometryReader { geo in
                let w = geo.size.width
                VStack(spacing: 4) {
                    // Scrub bar: click or drag to move the playhead.
                    Rectangle().fill(.quaternary).frame(height: 14)
                        .gesture(DragGesture(minimumDistance: 0).onChanged {
                            editor.seek(min(max($0.location.x / w, 0), 1) * total)
                        })
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                            segmentView(seg, index: i, width: seg.duration / total * w)
                                .onTapGesture { loc in
                                    select(seg.id)
                                    editor.seek(segments.startTime(of: i) + loc.x / (seg.duration / total * w) * seg.duration)
                                }
                                .draggable(seg.id.uuidString)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let s = items.first, let id = UUID(uuidString: s) else { return false }
                                    editor.move(id, to: seg.id)
                                    return true
                                }
                                .contextMenu {
                                    Button("Rename…") { editor.renaming = .segment(seg.id) }
                                    Button("Delete") {
                                        if !editor.selection.contains(seg.id) { editor.selection = [seg.id] }
                                        editor.deleteSelection()
                                    }
                                    Divider()
                                    Button("Save Video") { Task { await editor.save(take) } }.disabled(editor.exporting)
                                }
                        }
                    }
                    .animation(.snappy, value: segments)
                }
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(.red).frame(width: 2)
                        .offset(x: min(editor.currentTime / total, 1) * w - 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 80)
        }
    }

    private func segmentView(_ seg: Segment, index: Int, width: Double) -> some View {
        let selected = editor.selection.contains(seg.id)
        return RoundedRectangle(cornerRadius: 4)
            .fill(Color(hue: Double(index % 6) / 6, saturation: 0.45, brightness: 0.75).gradient)
            .overlay(alignment: .topLeading) {
                Text(seg.name ?? "Clip \(index + 1)")
                    .font(.caption).lineLimit(1).padding(4)
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(selected ? Color.accentColor : .black.opacity(0.3), lineWidth: selected ? 3 : 1)
            }
            .frame(width: max(width, 1))
            .contentShape(Rectangle())
    }

    /// Click selects one; ⌘/⇧-click toggles.
    private func select(_ id: Segment.ID) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) || mods.contains(.shift) {
            if editor.selection.contains(id) { editor.selection.remove(id) } else { editor.selection.insert(id) }
        } else {
            editor.selection = [id]
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none
        v.player = player
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}

private func format(_ t: Double) -> String {
    let t = max(0, t.isFinite ? t : 0)
    return String(format: "%d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
}
