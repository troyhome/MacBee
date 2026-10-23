import CoreAudio
import Foundation

/// Lists output devices and controls the things bit-perfect playback needs:
/// sample rate, physical bit depth, exclusive (hog) mode and hardware volume.
@MainActor
public final class AudioDeviceManager {

    /// Called on the main queue when devices are added/removed or the system default changes.
    public var onDevicesChanged: (@MainActor () -> Void)?

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init() {
        listen(kAudioHardwarePropertyDevices)
        listen(kAudioHardwarePropertyDefaultOutputDevice)
    }

    deinit {
        for (address, block) in listeners {
            var a = address
            AudioObjectRemovePropertyListenerBlock(system, &a, .main, block)
        }
    }

    // MARK: - Devices

    public func outputDevices() -> [AudioDevice] {
        let ids = (try? HAL.getArray(system, HAL.address(kAudioHardwarePropertyDevices), of: AudioObjectID.self)) ?? []
        return ids.filter(hasOutputStreams).compactMap(makeDevice)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func defaultOutputDevice() -> AudioDevice? {
        guard let id = try? HAL.get(system, HAL.address(kAudioHardwarePropertyDefaultOutputDevice),
                                    initial: AudioObjectID(kAudioObjectUnknown)),
              id != kAudioObjectUnknown else { return nil }
        return makeDevice(id)
    }

    /// The device for a saved UID, falling back to the system default.
    public func resolveDevice(uid: String?) -> AudioDevice? {
        if let uid, let match = outputDevices().first(where: { $0.uid == uid }) { return match }
        return defaultOutputDevice()
    }

    // MARK: - Sample rate

    public func nominalSampleRate(of id: AudioObjectID) -> Double {
        (try? HAL.get(id, HAL.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))) ?? 0
    }

    /// Switches the DAC's rate and waits until the hardware confirms it.
    public func setNominalSampleRate(_ rate: Double, on id: AudioObjectID, timeout: Duration = .seconds(2)) async throws {
        if abs(nominalSampleRate(of: id) - rate) < 0.5 { return }
        try HAL.set(id, HAL.address(kAudioDevicePropertyNominalSampleRate), Float64(rate))

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if abs(nominalSampleRate(of: id) - rate) < 0.5 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AudioEngineError.sampleRateChangeTimedOut(rate)
    }

    // MARK: - Physical format (bit depth)

    /// Picks the highest integer bit depth the device offers at `sampleRate`. Returns the chosen depth.
    @discardableResult
    public func selectHighestBitDepth(on id: AudioObjectID, sampleRate: Double) throws -> Int? {
        guard let stream = firstOutputStream(of: id) else { return nil }
        let current = try HAL.get(stream, HAL.address(kAudioStreamPropertyPhysicalFormat),
                                  initial: AudioStreamBasicDescription())
        let available = try HAL.getArray(stream, HAL.address(kAudioStreamPropertyAvailablePhysicalFormats),
                                         of: AudioStreamRangedDescription.self)

        let candidates = available.filter { d in
            let f = d.mFormat
            let rateOK = abs(f.mSampleRate - sampleRate) < 0.5
                || (sampleRate >= d.mSampleRateRange.mMinimum && sampleRate <= d.mSampleRateRange.mMaximum)
            return f.mFormatID == kAudioFormatLinearPCM
                && (f.mFormatFlags & kAudioFormatFlagIsFloat) == 0
                && f.mChannelsPerFrame == current.mChannelsPerFrame
                && rateOK
        }
        guard var best = candidates.max(by: { $0.mFormat.mBitsPerChannel < $1.mFormat.mBitsPerChannel })?.mFormat else {
            return currentBitDepth(of: id)
        }
        best.mSampleRate = sampleRate
        if best.mBitsPerChannel != current.mBitsPerChannel || (current.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
            try HAL.set(stream, HAL.address(kAudioStreamPropertyPhysicalFormat), best)
        }
        return Int(best.mBitsPerChannel)
    }

    public func currentBitDepth(of id: AudioObjectID) -> Int? {
        guard let stream = firstOutputStream(of: id),
              let f = try? HAL.get(stream, HAL.address(kAudioStreamPropertyPhysicalFormat),
                                   initial: AudioStreamBasicDescription()),
              f.mBitsPerChannel > 0 else { return nil }
        return Int(f.mBitsPerChannel)
    }

    // MARK: - Exclusive (hog) mode

    public func hogModeOwner(of id: AudioObjectID) -> pid_t {
        (try? HAL.get(id, HAL.address(kAudioDevicePropertyHogMode), initial: pid_t(-1))) ?? -1
    }

    public func ownsHogMode(_ id: AudioObjectID) -> Bool { hogModeOwner(of: id) == getpid() }

    /// Note: writing this property toggles ownership, so always check the owner first.
    public func acquireHogMode(on device: AudioDevice) throws {
        let owner = hogModeOwner(of: device.id)
        if owner == getpid() { return }
        guard owner == -1 else { throw AudioEngineError.deviceBusy(device.name) }
        try HAL.set(device.id, HAL.address(kAudioDevicePropertyHogMode), getpid())
        // The App Store sandbox may accept the request without handing the device over. Say so instead of
        // showing exclusive mode as on.
        guard ownsHogMode(device.id) else { throw AudioEngineError.exclusiveModeUnavailable(device.name) }
    }

    public func releaseHogMode(on id: AudioObjectID) {
        guard ownsHogMode(id) else { return }
        try? HAL.set(id, HAL.address(kAudioDevicePropertyHogMode), pid_t(-1))
    }

    // MARK: - Hardware volume

    /// Channels that carry a settable volume control: [main] or [left, right]. Empty if none.
    func volumeElements(of id: AudioObjectID) -> [AudioObjectPropertyElement] {
        let main = HAL.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
        if HAL.isSettable(id, main) { return [kAudioObjectPropertyElementMain] }
        let channels: [AudioObjectPropertyElement] = [1, 2].filter {
            HAL.isSettable(id, HAL.address(kAudioDevicePropertyVolumeScalar,
                                           scope: kAudioDevicePropertyScopeOutput, element: $0))
        }
        return channels
    }

    public func hardwareVolume(of id: AudioObjectID) -> Float? {
        guard let element = volumeElements(of: id).first else { return nil }
        return try? HAL.get(id, HAL.address(kAudioDevicePropertyVolumeScalar,
                                            scope: kAudioDevicePropertyScopeOutput, element: element),
                            initial: Float32(0))
    }

    public func setHardwareVolume(_ volume: Float, on id: AudioObjectID) throws {
        let v = Float32(min(max(volume, 0), 1))
        for element in volumeElements(of: id) {
            try HAL.set(id, HAL.address(kAudioDevicePropertyVolumeScalar,
                                        scope: kAudioDevicePropertyScopeOutput, element: element), v)
        }
    }

    // MARK: - Private

    private func makeDevice(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = try? HAL.getString(id, HAL.address(kAudioDevicePropertyDeviceUID)) else { return nil }
        let name = (try? HAL.getString(id, HAL.address(kAudioObjectPropertyName))) ?? "Unknown Device"
        let maker = (try? HAL.getString(id, HAL.address(kAudioObjectPropertyManufacturer))) ?? ""
        let ranges = (try? HAL.getArray(id, HAL.address(kAudioDevicePropertyAvailableNominalSampleRates),
                                        of: AudioValueRange.self)) ?? []
        let rates = SampleRatePolicy.expand(ranges: ranges.map { ($0.mMinimum, $0.mMaximum) })
        return AudioDevice(id: id, uid: uid, name: name, manufacturer: maker,
                           supportedSampleRates: rates, hasHardwareVolume: !volumeElements(of: id).isEmpty,
                           isVirtual: isVirtual(id))
    }

    /// Virtual drivers report "virtual"; some report nothing at all, so treat unknown as virtual too.
    private func isVirtual(_ id: AudioObjectID) -> Bool {
        let transport = (try? HAL.get(id, HAL.address(kAudioDevicePropertyTransportType), initial: UInt32(0))) ?? 0
        return transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeUnknown
    }

    private func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        firstOutputStream(of: id) != nil
    }

    private func firstOutputStream(of id: AudioObjectID) -> AudioStreamID? {
        let streams = try? HAL.getArray(id, HAL.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput),
                                        of: AudioStreamID.self)
        return streams?.first
    }

    private func listen(_ selector: AudioObjectPropertySelector) {
        var address = HAL.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Registered on the main queue, so we are on the main actor here.
            MainActor.assumeIsolated { self?.onDevicesChanged?() }
        }
        if AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr {
            listeners.append((address, block))
        }
    }
}
