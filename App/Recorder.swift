import AVFoundation
import SwiftUI
import UIKit

enum Mode: String, CaseIterable, Identifiable {
    case chest, table, tap
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chest: return "Chest + finger"
        case .table: return "Table control"
        case .tap: return "Tap sync test"
        }
    }
    var instructions: String {
        switch self {
        case .chest:
            return "Sit back, relaxed, hand near heart level. Hold the phone flat on the lower sternum, SCREEN AGAINST "
                + "YOUR CHEST, rear camera facing out. Cover the camera and flash with your index fingertip, light steady "
                + "pressure. Breathe normally, don't talk or move. You'll hear when recording starts and ends."
        case .table:
            return "Lay the phone screen-down on a firm table. Rest your fingertip on the camera and flash with the same "
                + "pressure as usual. The phone is not on your chest, so any 'heartbeat' found in the accelerometer "
                + "means your finger's pulse is leaking into it."
        case .tap:
            return "Hold the phone as in Chest mode with your fingertip on the camera. Once recording starts, tap the "
                + "back of the phone firmly next to the camera with another finger about every 4 seconds (6 to 8 taps). "
                + "This checks camera and accelerometer timing."
        }
    }
}

enum Phase { case idle, preparing, recording, saving, done }

struct LiveStats {
    var fps = 0.0, accHz = 0.0
    var r: Float = 0, g: Float = 0, b: Float = 0
    var sat: Float = 0, iso: Float = 0, expMs: Float = 0
    var ppg: [Double] = []
    var scg: [Double] = []
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class Recorder: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var remaining = 0
    @Published var mode: Mode = .chest
    @Published var fps = 120
    @Published var duration = 60
    @Published var accHz = 400
    @Published var live = LiveStats()
    @Published var errorMessage: String?
    @Published var summary: [SummaryRow] = []
    @Published var recordings: [URL] = SessionStore.list()
    @Published var shareItem: ShareItem?
    @Published var cuffSBP = ""
    @Published var cuffDBP = ""
    @Published var notes = ""
    @Published var savedNote = ""

    let settleSeconds = 7.0
    private let camera = CameraPPG()
    private let motion = MotionSCG()
    private let speech = AVSpeechSynthesizer()
    private var timer: Timer?
    private var tStart = 0.0, tRecord = 0.0, tEnd = 0.0
    private var markers: [(Double, String)] = []
    private var cameraInfo: [String: Any] = [:]
    private(set) var currentFolder: URL?
    private var meta: [String: Any] = [:]

    func start() async {
        errorMessage = nil
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            errorMessage = "Camera permission is off. Turn it on in Settings > HC Capture."
            return
        }
        guard motion.accelerometerAvailable else { errorMessage = "Accelerometer not available."; return }
        do {
            cameraInfo = try camera.configure(targetFPS: Double(fps))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        markers = []
        cuffSBP = ""; cuffDBP = ""; notes = ""; savedNote = ""
        UIApplication.shared.isIdleTimerDisabled = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        speak(mode == .table ? "Place your finger on the camera." : "Place the phone now. Recording starts shortly.")

        phase = .preparing
        remaining = Int(settleSeconds)
        await camera.start()
        motion.start(hz: Double(accHz))
        tStart = HostClock.now
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = HostClock.now
        switch phase {
        case .preparing:
            let left = settleSeconds - (now - tStart)
            remaining = max(0, Int(left.rounded(.up)))
            if left <= 0 {
                camera.freezeExposure()
                tRecord = HostClock.now
                phase = .recording
                // haptic only, no sound: the speaker would shake the accelerometer
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        case .recording:
            let left = Double(duration) - (now - tRecord)
            remaining = max(0, Int(left.rounded(.up)))
            if left <= 0 { Task { await finish() } }
        default:
            break
        }
        updateLive()
    }

    private func updateLive() {
        let rp = camera.recent(seconds: 4)
        let ra = motion.recentAcc(seconds: 4)
        var s = LiveStats()
        if let last = rp.last, let first = rp.first, rp.count > 1 {
            s.fps = Double(rp.count - 1) / (last.t - first.t)
            s.r = last.r; s.g = last.g; s.b = last.b; s.sat = last.satAny * 100; s.iso = last.iso; s.expMs = last.expMs
            let stride = max(1, rp.count / 300)
            s.ppg = Swift.stride(from: 0, to: rp.count, by: stride).map { -Double(rp[$0].g) }
        }
        if let last = ra.last, let first = ra.first, ra.count > 1 {
            s.accHz = Double(ra.count - 1) / (last.t - first.t)
            let stride = max(1, ra.count / 300)
            s.scg = Swift.stride(from: 0, to: ra.count, by: stride).map { -ra[$0].z }
        }
        live = s
    }

    func mark() { markers.append((HostClock.now, "mark")) }

    func stopEarly() {
        guard phase == .preparing || phase == .recording else { return }
        if phase == .preparing { tRecord = HostClock.now }
        Task { await finish() }
    }

    private func finish() async {
        guard phase != .saving && phase != .done else { return }
        tEnd = HostClock.now
        phase = .saving
        timer?.invalidate(); timer = nil
        motion.stop()
        await camera.stop()
        UIApplication.shared.isIdleTimerDisabled = false

        let (ppg, dropped) = camera.takeAll()
        let (acc, gyro) = motion.takeAll()
        let folder = SessionStore.newFolder(mode: mode.rawValue)
        currentFolder = folder
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        iso8601.timeZone = TimeZone.current
        meta = [
            "app": "HC Capture 0.1.0",
            "created_local": iso8601.string(from: Date()),
            "device_model": SessionStore.modelIdentifier,
            "os_version": UIDevice.current.systemVersion,
            "mode": mode.rawValue,
            "fps_target": fps,
            "acc_rate_requested_hz": accHz,
            "duration_target_s": duration,
            "settle_s": settleSeconds,
            "record_start_t": tRecord,
            "record_end_t": tEnd,
            "clock": "host clock seconds (mach time); camera PTS converted from session sync clock; CoreMotion timestamps",
            "camera": cameraInfo,
            "dropped_frames": dropped,
            "units": ["acc": "g", "gyro": "rad/s", "ppg": "mean 0-255 per channel"],
            "orientation_protocol": mode == .table ? "screen down on table" : "screen against chest, -z = out of chest",
            "cuff_sbp": NSNull(), "cuff_dbp": NSNull(), "notes": "",
        ]
        let rows = SessionStore.summarize(ppg: ppg, acc: acc, dropped: dropped, targetFPS: Double(fps),
                                          tRecord: tRecord, tEnd: tEnd)
        let m = meta, mk = markers, tr = tRecord, te = tEnd
        do {
            try await Task.detached(priority: .userInitiated) {
                try SessionStore.write(folder: folder, ppg: ppg, acc: acc, gyro: gyro, markers: mk,
                                       tRecord: tr, tEnd: te, meta: m)
            }.value
        } catch {
            errorMessage = "Saving failed: \(error.localizedDescription)"
        }
        summary = rows
        recordings = SessionStore.list()
        phase = .done
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        speak("Done.")
    }

    func saveCuff() {
        guard let folder = currentFolder else { return }
        var m = SessionStore.readMeta(folder: folder)
        m["cuff_sbp"] = Double(cuffSBP).map { $0 as Any } ?? NSNull()
        m["cuff_dbp"] = Double(cuffDBP).map { $0 as Any } ?? NSNull()
        m["notes"] = notes
        do {
            try SessionStore.writeMeta(folder: folder, meta: m)
            savedNote = "Saved."
        } catch {
            savedNote = "Could not save: \(error.localizedDescription)"
        }
    }

    func newRecording() {
        phase = .idle
        summary = []
        live = LiveStats()
    }

    func share(_ url: URL) {
        do { shareItem = ShareItem(url: try SessionStore.zip(url)) } catch { errorMessage = error.localizedDescription }
    }

    func shareAll() { share(SessionStore.root) }

    func delete(at offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: recordings[i]) }
        recordings = SessionStore.list()
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        speech.speak(u)
    }
}
