import AppKit
import Libmpv
import Observation

/// Plays a video with libmpv (MKV, MP4, HEVC, 4K HDR and nearly anything else) into an `MPVVideoView`.
/// All calls happen on the main thread; mpv's own threads do the decoding.
@MainActor
@Observable
public final class MPVPlayer {
    public struct Track: Identifiable, Hashable, Sendable {
        public let id: Int
        public let kind: String // "audio" or "sub"
        public let title: String
        public let isSelected: Bool
    }

    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var isPaused = false
    public private(set) var isBuffering = false
    public private(set) var audioTracks: [Track] = []
    public private(set) var subtitleTracks: [Track] = []
    /// The file finished playing.
    public private(set) var reachedEnd = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private var handle: OpaquePointer?
    /// A file asked for before mpv was ready (its view not yet on screen).
    @ObservationIgnored private var pending: (url: URL, start: Double)?
    @ObservationIgnored private var isShutDown = false
    @ObservationIgnored let layer = MPVMetalLayer()
    /// The view the picture is drawn in; `MPVVideoView` places it.
    @ObservationIgnored public private(set) lazy var surface: MPVSurfaceView = {
        let view = MPVSurfaceView(frame: .zero)
        view.player = self
        return view
    }()

    /// Which `MPVVideoView` shows the picture ("main" or "mini"); set it before showing the other one.
    public var activeHost = "main"

    public init() {}

    /// Starts mpv and draws into the view's layer. Call once the view is on screen.
    func start(in view: NSView) {
        guard handle == nil, !isShutDown, let mpv = mpv_create() else { return }
        handle = mpv
        view.layer = layer
        view.wantsLayer = true
        var layerPointer = layer
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerPointer)
        for (name, value) in [("vo", "gpu-next"), ("gpu-api", "vulkan"), ("gpu-context", "moltenvk"),
                              ("hwdec", "videotoolbox"), ("ytdl", "no"), ("keep-open", "yes"),
                              ("input-media-keys", "no"), ("input-default-bindings", "no"), ("osc", "no"),
                              ("subs-match-os-language", "yes"), ("subs-fallback", "yes"),
                              ("audio-display", "no"), ("terminal", "no")] {
            mpv_set_option_string(mpv, name, value)
        }
        guard mpv_initialize(mpv) >= 0 else {
            errorMessage = "The video player couldn't start."
            return
        }
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NONE)
        let context = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            DispatchQueue.main.async {
                Unmanaged<MPVPlayer>.fromOpaque(context).takeUnretainedValue().readEvents()
            }
        }, context)
        if let pending {
            self.pending = nil
            load(pending.url, startAt: pending.start)
        }
    }

    /// Plays a file, optionally from a position in seconds.
    public func load(_ url: URL, startAt seconds: Double = 0) {
        guard handle != nil else {
            pending = (url, seconds)
            return
        }
        reachedEnd = false
        errorMessage = nil
        var options = ""
        if seconds > 1 { options = "start=\(Int(seconds))" }
        command(["loadfile", url.path, "replace", "-1", options])
        setFlag("pause", false)
    }

    public func togglePause() { setFlag("pause", !isPaused) }
    public func pause() { setFlag("pause", true) }

    public func seek(to seconds: Double) {
        command(["seek", String(max(0, seconds)), "absolute"])
    }

    public func seek(by seconds: Double) {
        command(["seek", String(seconds), "relative"])
    }

    /// 0…100.
    public func setVolume(_ volume: Double) {
        var value = volume
        if let handle { mpv_set_property(handle, "volume", MPV_FORMAT_DOUBLE, &value) }
    }

    /// Picks an audio or subtitle track (nil turns subtitles off).
    public func select(_ track: Track?, kind: String) {
        let property = kind == "audio" ? "aid" : "sid"
        if let handle { mpv_set_property_string(handle, property, track.map { String($0.id) } ?? "no") }
    }

    /// Stops playback and shuts mpv down. The player can't be used afterwards.
    public func shutdown() {
        isShutDown = true
        guard let handle else { return }
        self.handle = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)
    }

    func property(_ name: String) -> String? {
        guard let handle, let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    func setString(_ name: String, _ value: String) {
        if let handle { mpv_set_property_string(handle, name, value) }
    }

    func resize(to size: CGSize, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true) // no animated stretching while the window resizes
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        CATransaction.commit()
        scheduleRefit()
    }

    @ObservationIgnored private var refitTask: Task<Void, Never>?
    @ObservationIgnored private var refitWhenPlaying = false

    /// mpv (with MoltenVK) only measures its picture size when the video's shape changes, so after the view
    /// changes size (a window resize, or moving to the mini player) it keeps drawing at the old size and only
    /// a corner shows. Briefly overriding the aspect by an invisible amount makes it measure again.
    private func scheduleRefit() {
        refitTask?.cancel()
        refitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200)) // wait for a window drag to settle
            guard let self, !Task.isCancelled, self.handle != nil else { return }
            let target = self.layer.drawableSize
            guard let dims = self.property("osd-dimensions"),
                  !dims.contains("\"w\":\(Int(target.width)),\"h\":\(Int(target.height))"),
                  let aspect = self.property("video-params/aspect").flatMap(Double.init), aspect > 0 else { return }
            // A paused picture doesn't re-measure, so wait until playback resumes.
            guard !self.isPaused else { self.refitWhenPlaying = true; return }
            self.setString("video-aspect-override", String(aspect * 1.0005))
            try? await Task.sleep(for: .milliseconds(150))
            self.setString("video-aspect-override", "no")
        }
    }

    // MARK: - mpv plumbing

    private func readEvents() {
        while let handle, let event = mpv_wait_event(handle, 0) {
            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                return
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.pointee.data else { continue }
                let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                apply(property)
            case MPV_EVENT_END_FILE:
                if let data = event.pointee.data {
                    let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    if end.reason == MPV_END_FILE_REASON_ERROR {
                        errorMessage = "This video couldn't be played (\(String(cString: mpv_error_string(end.error))))."
                    }
                }
            case MPV_EVENT_SHUTDOWN:
                return
            default:
                continue
            }
        }
    }

    private func apply(_ property: mpv_event_property) {
        let name = String(cString: property.name)
        switch name {
        case "track-list":
            loadTracks()
            return
        default: break
        }
        guard let data = property.data else { return }
        switch (name, property.format) {
        case ("time-pos", MPV_FORMAT_DOUBLE): position = data.load(as: Double.self)
        case ("duration", MPV_FORMAT_DOUBLE): duration = data.load(as: Double.self)
        case ("pause", MPV_FORMAT_FLAG):
            isPaused = data.load(as: Int32.self) != 0
            if !isPaused && refitWhenPlaying {
                refitWhenPlaying = false
                scheduleRefit()
            }
        case ("paused-for-cache", MPV_FORMAT_FLAG): isBuffering = data.load(as: Int32.self) != 0
        case ("eof-reached", MPV_FORMAT_FLAG): reachedEnd = data.load(as: Int32.self) != 0
        default: break
        }
    }

    /// Reads the audio and subtitle tracks (mpv gives them as JSON).
    private func loadTracks() {
        guard let handle, let raw = mpv_get_property_string(handle, "track-list") else { return }
        defer { mpv_free(raw) }
        guard let data = String(cString: raw).data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        var audio: [Track] = []
        var subs: [Track] = []
        for item in list {
            guard let id = item["id"] as? Int, let type = item["type"] as? String else { continue }
            let language = (item["lang"] as? String).flatMap { Locale.current.localizedString(forLanguageCode: $0) }
            let parts = [item["title"] as? String, language, item["codec"] as? String].compactMap { $0 }
            let title = parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
            let track = Track(id: id, kind: type, title: title, isSelected: item["selected"] as? Bool ?? false)
            if type == "audio" { audio.append(track) } else if type == "sub" { subs.append(track) }
        }
        audioTracks = audio
        subtitleTracks = subs
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let handle else { return }
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
    }

    func command(_ words: [String]) {
        guard let handle else { return }
        var cStrings: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) }
        cStrings.append(nil)
        defer { cStrings.forEach { free($0) } }
        cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { pointer in
                _ = mpv_command(handle, pointer)
            }
        }
    }
}

/// CAMetalLayer with MoltenVK workarounds (from mpv/MPVKit): ignore 1x1 drawable sizes that cause flicker,
/// and switch on HDR (EDR) only from the main thread.
final class MPVMetalLayer: CAMetalLayer {
    override init() {
        super.init()
        // While a resize is in progress, show the whole old picture scaled, never a cropped part of it.
        contentsGravity = .resizeAspect
        backgroundColor = NSColor.black.cgColor
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var drawableSize: CGSize {
        get { super.drawableSize }
        set { if Int(newValue.width) > 1 && Int(newValue.height) > 1 { super.drawableSize = newValue } }
    }

    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync { super.wantsExtendedDynamicRangeContent = newValue }
            }
        }
    }
}
