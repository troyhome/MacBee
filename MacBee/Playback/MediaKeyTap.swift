import AppKit
import ApplicationServices
import Observation

/// Makes the keyboard's play/pause, next and previous keys always control MacBee while it has music loaded,
/// even when another player (Qobuz, Spotify, Apple Music) is open and would normally get them.
///
/// It catches the keys before macOS hands them to the "Now Playing" app, which needs the Accessibility
/// permission (System Settings > Privacy & Security > Accessibility). Without the permission, or when MacBee
/// has nothing loaded, the keys work as usual through Now Playing (`NowPlayingService`).
@MainActor
@Observable
final class MediaKeyTap {
    /// The keys are being caught.
    private(set) var isActive = false
    /// macOS hasn't given MacBee the Accessibility permission yet.
    private(set) var needsPermission = false

    @ObservationIgnored private let player: PlayerViewModel
    @ObservationIgnored fileprivate var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?

    init(player: PlayerViewModel) {
        self.player = player
    }

    /// Starts catching the keys. With `askForPermission`, macOS shows its permission prompt if needed.
    func start(askForPermission: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: askForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            needsPermission = true
            return
        }
        needsPermission = false
        let systemDefined = CGEventMask(1 << 14) // NX_SYSDEFINED: media and other special keys
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: systemDefined, callback: mediaKeyCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isActive = true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        isActive = false
    }

    /// Handles a media key. Returns true when MacBee took it (so no other app gets it).
    fileprivate func handle(key: Int, isDown: Bool, isRepeat: Bool) -> Bool {
        guard player.currentTrack != nil else { return false } // nothing loaded: leave the keys to others
        let action: (() -> Void)?
        switch key {
        case 16: action = { self.player.togglePlayPause() }   // play/pause
        case 17, 19: action = { self.player.next() }          // next, fast-forward
        case 18, 20: action = { self.player.previous() }      // previous, rewind
        default: return false
        }
        if isDown && !isRepeat { action?() }
        return true // swallow both key-down and key-up
    }
}

/// Called by macOS for every special key press, on the main run loop.
private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // macOS switches a slow tap off; turn it back on.
        MainActor.assumeIsolated { if let port = tap.tap { CGEvent.tapEnable(tap: port, enable: true) } }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let key = NSEvent(cgEvent: event), key.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let code = (key.data1 & 0xFFFF0000) >> 16
    let flags = key.data1 & 0x0000FFFF
    let isDown = (flags & 0xFF00) >> 8 == 0x0A
    let isRepeat = flags & 0x1 == 1
    let taken = MainActor.assumeIsolated { tap.handle(key: code, isDown: isDown, isRepeat: isRepeat) }
    return taken ? nil : Unmanaged.passUnretained(event)
}
