# QuickCut

Minimal Mac video cutter (SwiftUI + AVFoundation, macOS 15+).

    ./build.sh && open QuickCut.app

`./build.sh --release` builds the copy that checks for updates. Releasing: [docs/RELEASING.md](docs/RELEASING.md).

- ⌘O open videos · Space play/pause · ⌘B cut at playhead · ⌫ delete selected segments · ⌘S save
- Click a segment to select (⌘/⇧-click for more), drag a segment onto another to reorder
- Right-click a segment or sidebar video for Rename / Save Video. Saved files go next to the original as `<name> edit.mov`.
