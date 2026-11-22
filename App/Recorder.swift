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
            return "Hold the phone as in Chest mode with your fingertip on the camera. Once recording starts, about every "
                + "4 seconds lift that fingertip about 1 cm and tap it straight back down onto the camera, firmly enough "
                + "to feel it (8 taps). Each tap shows up in both the camera and the accelerometer at the same moment, "
                + "which checks their timing."
        }
    }
}

enum Phase { case idle, preparing, recording, saving, done }

struct LiveStats {
    var fps = 0.0, accHz = 0.0
    var r: Float = 0, g: Float = 0, b: Float = 0
    var sat: Float = 0, iso: Float = 0, expMs: Float = 0
    var ppg: [Double] = []          // finger pulse, filtered 0.5-10 Hz, last 4 s
    var scg: [Double] = []          // chest -z, filtered 5-40 Hz, last 4 s
    var beat = LiveBeat()           // heart rate + chest beat average, last 20 s
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
    /// Remembered between app launches, so every recording on this phone uses the same lens.
    @Published var lens: CameraLens = CameraLens.remembered() {
        didSet { UserDefaults.standard.set(lens.rawValue, forKey: "hc.lens") }
    }
    /// Flash starts at 80% every recording and is raised (90%, then 100%) only while positioning, and only if
    /// the finger is too dim with the camera already at its most sensitive. It never changes during the recording.
    let torchStartPct = 80
    @Published var torchNowPct = 80
    @Published var colourChannel: String? = ColourProfile.channel
    @Published var colourMessage = ""
    @Published var settle = 10
    @Published var live = LiveStats()
    @Published var errorMessage: String?
    @Published var summary: [SummaryRow] = []
    @Published var recordings: [URL] = SessionStore.list()
    @Published var shareItem: ShareItem?
    @Published var cuffSBP = ""
    @Published var cuffDBP = ""
    @Published var notes = ""
    @Published var savedNote = ""
    @Published var analysis: AnalysisResult?
    @Published var analyzing = false
    @Published var analysisError: String?

    var settleSeconds: Double { Double(settle) }
    private let camera = CameraPPG()
    private let motion = MotionSCG()
    private let speech = AVSpeechSynthesizer()
    private var timer: Timer?
    private var tStart = 0.0, tRecord = 0.0, tEnd = 0.0
    private var markers: [(Double, String)] = []
    private var cameraInfo: [String: Any] = [:]
    private(set) var currentFolder: URL?
    private var meta: [String: Any] = [:]
    private var lastSlow = 0.0
    private var slow = LiveBeat()
    private var liveChannel = "g"
    private var lastTorchStep = 0.0
    private var flags: [String] = []
    private var lightAtStart = 0.0

    func start() async {
        errorMessage = nil
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            errorMessage = "Camera permission is off. Turn it on in Settings > HC Capture."
            return
        }
        guard motion.accelerometerAvailable else { errorMessage = "Accelerometer not available."; return }
        do {
            torchNowPct = torchStartPct
            cameraInfo = try camera.configure(targetFPS: Double(fps), lens: lens, torchLevel: Double(torchStartPct) / 100)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        markers = []
        lastSlow = 0; slow = LiveBeat(); liveChannel = ColourProfile.channel ?? "g"
        lastTorchStep = 0; flags = []; lightAtStart = 0; colourMessage = ""
        analysis = nil; analysisError = nil; analyzing = false
        cuffSBP = ""; cuffDBP = ""; notes = ""; savedNote = ""
        UIApplication.shared.isIdleTimerDisabled = true
        // screen goes dark and ignores touches while it is against the chest (or face-down on the table)
        UIDevice.current.isProximityMonitoringEnabled = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        speak(mode == .table ? "Place your finger on the camera, check the light bar, then lay the phone screen down."
              : "Place your finger, check the light bar, then put the phone on your chest.")

        phase = .preparing
        remaining = Int(settleSeconds)
        await camera.start()
        motion.start(hz: Double(accHz))
        tStart = HostClock.now
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = HostClock.now
        switch phase {
        case .preparing:
            let left = settleSeconds - (now - tStart)
            remaining = max(0, Int(left.rounded(.up)))
            // raise the flash one step if the finger is dim and the camera can't brighten any more by itself
            if left > 1.5 && now - tStart > 3 && now - lastTorchStep > 2 && torchNowPct < 100 {
                let light = recentLight(1.0)
                if light > 0 && light < 150 && camera.atSensitivityLimit {
                    torchNowPct = min(100, torchNowPct + 10)
                    camera.setTorch(level: Double(torchNowPct) / 100)
                    lastTorchStep = now
                }
            }
            if left <= 0 {
                checkLightAtStart()
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

    /// Mean of the brightest colour over the last `seconds` (0 if no frames yet).
    private func recentLight(_ seconds: Double) -> Double {
        let rp = camera.recent(seconds: seconds)
        guard rp.count > 10 else { return 0 }
        var s = 0.0
        for p in rp { s += Double(max(p.r, max(p.g, p.b))) }
        return s / Double(rp.count)
    }

    /// Flag the recording if the finger light is still too low when recording starts.
    private func checkLightAtStart() {
        let light = recentLight(1.0)
        lightAtStart = light
        cameraInfo["torch_level"] = Double(torchNowPct) / 100
        if light < 60 {
            flags.append(String(format: "Finger light too dark when recording started (%.0f of 255). The finger may not cover the camera and the flash.", light))
        } else if light < 100 && camera.atSensitivityLimit {
            flags.append(String(format: "Finger light below target when recording started (%.0f of 255) with the flash at %d%%.", light, torchNowPct))
        }
    }

    private func updateLive() {
        let rp = camera.recent(seconds: 5)
        let ra = motion.recentAcc(seconds: 5)
        var s = LiveStats()
        if let last = rp.last, let first = rp.first, rp.count > 1, last.t > first.t {
            s.fps = Double(rp.count - 1) / (last.t - first.t)
            s.r = last.r; s.g = last.g; s.b = last.b; s.sat = last.satAny * 100; s.iso = last.iso; s.expMs = last.expMs
            s.ppg = LiveDSP.ppgWave(rp, channel: liveChannel, show: 4)
        }
        if let last = ra.last, let first = ra.first, ra.count > 1, last.t > first.t {
            s.accHz = Double(ra.count - 1) / (last.t - first.t)
            s.scg = LiveDSP.scgWave(ra, show: 4)
        }
        let now = HostClock.now
        if now - lastSlow >= 1.0 {
            lastSlow = now
            slow = LiveDSP.beatSummary(ppg: camera.recent(seconds: 20), acc: motion.recentAcc(seconds: 20),
                                       channel: ColourProfile.channel)
            liveChannel = slow.channel
        }
        s.beat = slow
        live = s
    }

    func mark() { markers.append((HostClock.now, "mark")) }

    /// t = moment the press started (the button needs a hold, so the mark is back-dated to the press).
    func mark(at t: Double) { markers.append((t, "mark")) }

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
        UIDevice.current.isProximityMonitoringEnabled = false

        let (ppg, dropped) = camera.takeAll()
        let (acc, gyro) = motion.takeAll()
        let folder = SessionStore.newFolder(mode: mode.rawValue)
        currentFolder = folder
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        iso8601.timeZone = TimeZone.current
        meta = [
            "app": "HC Capture 0.3.3",
            "lens": lens.rawValue,
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
            "torch_level_start": Double(torchStartPct) / 100,
            "flash_raised": torchNowPct > torchStartPct,
            "light_at_start": lightAtStart,
            "flags": flags,
            "ppg_channel_locked": ColourProfile.channel.map { $0 as Any } ?? NSNull(),
            "colour_setup": ColourProfile.setup,
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
        runAnalysis(folder)
    }

    /// Full on-phone analysis (port of hc_analyze.py). Results are also saved in the recording's analysis folder.
    func runAnalysis(_ folder: URL) {
        analyzing = true
        analysisError = nil
        analysis = nil
        Task {
            let r = await Analyzer.analyzeAsync(folder: folder)
            switch r {
            case .success(let a0):
                let a = self.updateColourProfile(a0, folder: folder)
                self.analysis = a
                self.speak(self.spokenSummary(a))
            case .failure(let e):
                self.analysisError = e.localizedDescription
                self.speak("Analysis failed. See the screen.")
            }
            self.analyzing = false
            self.recordings = SessionStore.list()
        }
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
        analysis = nil
        analysisError = nil
    }

    func share(_ url: URL) {
        do { shareItem = ShareItem(url: try SessionStore.zip(url)) } catch { errorMessage = error.localizedDescription }
    }

    func shareAll() { share(SessionStore.root) }

    func delete(at offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: recordings[i]) }
        recordings = SessionStore.list()
    }

    /// Keep the finger colour fixed between recordings, choosing it automatically when needed.
    private func updateColourProfile(_ a: AnalysisResult, folder: URL) -> AnalysisResult {
        guard a.mode == "chest" || a.mode == "table" else { return a }
        var out = a
        if ColourProfile.channel != nil && a.channelSource == "locked" {
            if a.channelPassed == true {
                ColourProfile.fails = 0
            } else {
                ColourProfile.fails += 1
                if ColourProfile.fails >= 3 {
                    ColourProfile.channel = nil
                    ColourProfile.fails = 0
                    colourMessage = "The saved finger colour failed 3 recordings in a row. It will be chosen again automatically on the next recording."
                }
            }
        } else if ColourProfile.channel == nil && a.channelSource == "auto" && a.channelPassed == true {
            ColourProfile.setup += 1
            ColourProfile.channel = a.channel
            ColourProfile.fails = 0
            ColourProfile.chosenOn = ISO8601DateFormatter().string(from: Date())
            colourMessage = "Finger colour set to \(ColourProfile.name(a.channel)). It will be used for every recording from now on."
            var m = SessionStore.readMeta(folder: folder)
            m["ppg_channel_locked"] = a.channel
            m["colour_setup"] = ColourProfile.setup
            m["colour_chosen_here"] = true
            try? SessionStore.writeMeta(folder: folder, meta: m)
            out.colourSetup = ColourProfile.setup
            try? Analyzer.save(out, folder)
        }
        colourChannel = ColourProfile.channel
        return out
    }

    /// Start choosing the finger colour afresh (for example for a different person on this phone).
    func resetColour() {
        ColourProfile.channel = nil
        ColourProfile.fails = 0
        colourChannel = nil
        colourMessage = "The finger colour will be chosen again automatically on the next chest or table recording."
    }

    /// Short spoken result, because the screen faces the chest. Spoken only after recording ends.
    func spokenSummary(_ r: AnalysisResult) -> String {
        let core = spokenCore(r)
        var pre = ""
        if r.isFlagged { pre = "Recording flagged. " }
        var post = ""
        if r.channelSource == "auto" && r.colourSetup != nil && r.colourSetup == ColourProfile.setup
            && ColourProfile.channel == r.channel && (r.mode == "chest" || r.mode == "table") && !colourMessage.isEmpty {
            post = " Finger colour set to \(ColourProfile.name(r.channel))."
        }
        return pre + core + post
    }

    private func spokenCore(_ r: AnalysisResult) -> String {
        var red = Double.nan
        for c in r.channels where c.channel == "r" { red = c.mean }
        if red.isFinite && red < 60 {
            return "Finger signal too dark. The flash light is not reaching the camera. Move your finger, or try another lens."
        }
        if red.isFinite && red > 245 {
            return "Finger signal too bright. Press a little lighter."
        }
        if let t = r.tap {
            return "Found \(t.accTaps) taps in the accelerometer. The camera saw \(t.paired). "
                + (t.paired >= 4 ? "Good." : "Too few matched. Tap firmer, about every 4 seconds.")
        }
        var parts: [String] = []
        if r.hrPpg.isFinite { parts.append("Heart rate \(Int(r.hrPpg.rounded())).") }
        let b = r.bestLock
        if r.mode == "table" {
            parts.append(b.isFinite ? (b > 3 ? "Warning. Finger pulse is leaking into the accelerometer." : "No pulse leak. Good.")
                         : "Not enough beats.")
        } else if !b.isFinite {
            parts.append("Not enough beats for the heartbeat check.")
        } else if b > 6 {
            parts.append("Heartbeat clear in the chest signal.")
        } else if b > 3 {
            parts.append("Heartbeat weak in the chest signal.")
        } else {
            parts.append("No heartbeat found in the chest signal. Try moving the phone along the breastbone.")
        }
        return parts.joined(separator: " ")
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        speech.speak(u)
    }
}
