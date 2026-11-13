import AVFoundation
import Observation

/// A piece of the source file, in source seconds.
struct Segment: Identifiable, Equatable {
    var id = UUID()
    var name: String?
    var start: Double
    var end: Double
    var duration: Double { end - start }
}

extension Array where Element == Segment {
    var duration: Double { reduce(0) { $0 + $1.duration } }

    /// Segment index and offset inside it for a timeline time.
    func locate(_ t: Double) -> (index: Int, offset: Double)? {
        var acc = 0.0
        for (i, s) in enumerated() {
            if t < acc + s.duration { return (i, t - acc) }
            acc += s.duration
        }
        return nil
    }

    /// Timeline time where segment `index` starts.
    func startTime(of index: Int) -> Double { prefix(index).reduce(0) { $0 + $1.duration } }

    @discardableResult
    mutating func split(at t: Double, minLength: Double = 0.05) -> Bool {
        guard let (i, off) = locate(t), off >= minLength, self[i].duration - off >= minLength else { return false }
        var right = self[i]
        right.id = UUID()
        right.start += off
        self[i].end = right.start
        insert(right, at: i + 1)
        return true
    }

    /// Moves `id` into the position currently held by `target`.
    mutating func move(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = firstIndex(where: { $0.id == id }),
              let to = firstIndex(where: { $0.id == target }) else { return }
        insert(remove(at: from), at: to)
    }
}

/// A video file in the sidebar, with its edit.
@Observable final class Take: Identifiable {
    let id = UUID()
    var url: URL
    var segments: [Segment]
    var name: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL, duration: Double) {
        self.url = url
        segments = [Segment(start: 0, end: duration)]
    }
}

enum RenameTarget: Equatable {
    case take(Take.ID)
    case segment(Segment.ID)
}

@MainActor @Observable final class Editor {
    var takes: [Take] = []
    var selectedTakeID: Take.ID?
    var selection: Set<Segment.ID> = []
    var currentTime = 0.0
    var isPlaying = false
    var showOpen = false
    var exporting = false
    var renaming: RenameTarget?
    var error: String?

    let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    var take: Take? { takes.first { $0.id == selectedTakeID } }

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = t.seconds
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    // MARK: Files

    func open(_ urls: [URL]) async {
        for url in urls {
            do {
                let d = try await AVURLAsset(url: url).load(.duration).seconds
                takes.append(Take(url: url, duration: d))
            } catch {
                self.error = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if selectedTakeID == nil { selectedTakeID = takes.first?.id }
    }

    func save(_ take: Take) async {
        exporting = true
        defer { exporting = false }
        do {
            let comp = try await Self.composition(url: take.url, segments: take.segments)
            guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
                throw CocoaError(.featureUnsupported)
            }
            let dir = take.url.deletingLastPathComponent()
            var out = dir.appendingPathComponent("\(take.name) edit.mov")
            var n = 2
            while FileManager.default.fileExists(atPath: out.path) {
                out = dir.appendingPathComponent("\(take.name) edit \(n).mov"); n += 1
            }
            try await session.export(to: out, as: .mov)
            await open([out])
        } catch {
            self.error = "Couldn't save video: \(error.localizedDescription)"
        }
    }

    func rename(_ target: RenameTarget, to newName: String) {
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        switch target {
        case .take(let id):
            guard let take = takes.first(where: { $0.id == id }) else { return }
            let dest = take.url.deletingLastPathComponent()
                .appendingPathComponent(newName).appendingPathExtension(take.url.pathExtension)
            guard dest != take.url else { return }
            do {
                try FileManager.default.moveItem(at: take.url, to: dest)
                take.url = dest
                if id == selectedTakeID { reload() }
            } catch {
                self.error = "Couldn't rename: \(error.localizedDescription)"
            }
        case .segment(let id):
            guard let take, let i = take.segments.firstIndex(where: { $0.id == id }) else { return }
            take.segments[i].name = newName
        }
    }

    func currentName(of target: RenameTarget) -> String {
        switch target {
        case .take(let id): takes.first { $0.id == id }?.name ?? ""
        case .segment(let id): take?.segments.first { $0.id == id }?.name ?? ""
        }
    }

    // MARK: Editing

    func cut() {
        take?.segments.split(at: currentTime)
    }

    func deleteSelection() {
        guard let take, !selection.isEmpty else { return }
        take.segments.removeAll { selection.contains($0.id) }
        selection = []
        reload()
    }

    func move(_ id: Segment.ID, to target: Segment.ID) {
        take?.segments.move(id, to: target)
        reload()
    }

    // MARK: Playback

    func togglePlay() {
        if player.rate != 0 { player.pause() } else {
            if let take, currentTime >= take.segments.duration - 0.05 { seek(0) }
            player.play()
        }
        isPlaying = player.rate != 0
    }

    func seek(_ t: Double) {
        currentTime = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Rebuilds the player item from the current take's segments, keeping the playhead.
    func reload() {
        reloadTask?.cancel()
        guard let take else { player.replaceCurrentItem(with: nil); return }
        let t = min(currentTime, take.segments.duration)
        let (url, segments) = (take.url, take.segments)
        reloadTask = Task {
            do {
                let comp = try await Self.composition(url: url, segments: segments)
                guard !Task.isCancelled else { return }
                player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
                seek(t)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    static func composition(url: URL, segments: [Segment]) async throws -> AVComposition {
        let asset = AVURLAsset(url: url)
        let comp = AVMutableComposition()
        for type in [AVMediaType.video, .audio] {
            for src in try await asset.loadTracks(withMediaType: type) {
                guard let dst = comp.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                dst.preferredTransform = try await src.load(.preferredTransform)
                var at = CMTime.zero
                for s in segments {
                    let range = CMTimeRange(start: CMTime(seconds: s.start, preferredTimescale: 600),
                                            end: CMTime(seconds: s.end, preferredTimescale: 600))
                    try dst.insertTimeRange(range, of: src, at: at)
                    at = at + range.duration
                }
            }
        }
        return comp
    }
}
