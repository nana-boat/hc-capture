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
    var shortTitle: String {
        switch self {
        case .chest: return "Chest"
        case .table: return "Table"
        case .tap: return "Tap test"
        }
    }
    var instructions: String {
        switch self {
        case .chest:
            return "Sit back, relaxed, and rest for 5 minutes first. Tap Start, cover the camera and the flash with your "
                + "index fingertip and check the light bar. Then put the phone on your chest at the chosen site, turned as shown, "
                + "SCREEN AGAINST YOUR CHEST, on bare skin. "
                + "The app tells you when the phone is in place and how the heartbeat looks. When you're ready, double tap "
                + "the phone with your other hand; recording starts 3 seconds later. Breathe normally, don't talk or move."
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

/// Where the phone sits on the body (chest recordings). Saved with each recording as "placement".
/// 0.4.2: the site-test sites. The codes and turns match the laptop rules (RULES_site_test_v1.md).
enum BodyPlacement: String, CaseIterable, Identifiable {
    case sternum
    case sternumSideways = "sternum_sideways"
    case leftClavicle = "left_clavicle"
    case manubrium
    case rightClavicle = "right_clavicle"
    case midSternum = "mid_sternum"
    case diaphragm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sternum: return "Lower breastbone"
        case .sternumSideways: return "Lower breastbone, sideways"
        case .leftClavicle: return "Below left collarbone"
        case .manubrium: return "Top of breastbone"
        case .rightClavicle: return "Below right collarbone"
        case .midSternum: return "Mid-breastbone"
        case .diaphragm: return "Diaphragm area (old test)"
        }
    }
    /// Lower-case name for sentences.
    var name: String {
        switch self {
        case .sternum: return "lower breastbone"
        case .sternumSideways: return "lower breastbone, sideways"
        case .leftClavicle: return "below the left collarbone"
        case .manubrium: return "top of the breastbone"
        case .rightClavicle: return "below the right collarbone"
        case .midSternum: return "mid-breastbone"
        case .diaphragm: return "diaphragm area"
        }
    }
    /// Short label for lists.
    var short: String {
        switch self {
        case .sternum: return "breastbone"
        case .sternumSideways: return "breastbone sideways"
        case .leftClavicle: return "L collarbone"
        case .manubrium: return "top of breastbone"
        case .rightClavicle: return "R collarbone"
        case .midSternum: return "mid-breastbone"
        case .diaphragm: return "diaphragm"
        }
    }
    var spokenWhere: String {
        switch self {
        case .sternum, .sternumSideways: return "on your lower breastbone"
        case .leftClavicle: return "below your left collarbone"
        case .manubrium: return "on the top of your breastbone"
        case .rightClavicle: return "below your right collarbone"
        case .midSternum: return "on the middle of your breastbone"
        case .diaphragm: return "just below your breastbone"
        }
    }
    /// The turn each site expects (upright: long side along the body; sideways: long side across it).
    var allowsUpright: Bool { self == .sternum || self == .midSternum || self == .diaphragm }
    var allowsSideways: Bool { self != .sternum && self != .midSternum }
    var turnName: String {
        allowsUpright && allowsSideways ? "upright or sideways" : (allowsUpright ? "upright" : "sideways")
    }
    var turnTitle: String {
        allowsUpright && allowsSideways ? "Upright or sideways" : (allowsUpright ? "Upright" : "Sideways")
    }
    var turnTip: String {
        switch self {
        case .diaphragm: return "Lay the phone flat below the breastbone, upright or sideways."
        case .sternum, .midSternum: return "Hold the phone upright, camera end towards your chin."
        default: return "Turn the phone sideways: long side across your body, camera end towards the hand that holds it."
        }
    }
    var weakTip: String {
        switch self {
        case .sternum: return "Try moving the phone a little lower on the breastbone."
        case .diaphragm: return "Keep the phone flat and still, and press lightly."
        default: return "Keep the phone flat and still. Shift it about 1 cm if needed."
        }
    }
    var instructions: String {
        switch self {
        case .sternum:
            return "Upright: long side along the breastbone, camera end towards your chin. Bottom edge just above the bottom tip of the breastbone (where the ribs meet in a V), centred on the bone."
        case .sternumSideways:
            return "Sideways: long side across the body, camera end towards the hand that holds it. Centred on the lower breastbone, lower edge just above its bottom tip."
        case .leftClavicle:
            return "Sideways, below the LEFT collarbone: top edge 1 to 2 finger widths below the collarbone, inner end close to the breastbone."
        case .manubrium:
            return "Sideways, centred on the top of the breastbone: top edge just below the notch at the base of the neck."
        case .rightClavicle:
            return "Sideways, below the RIGHT collarbone: top edge 1 to 2 finger widths below the collarbone, inner end close to the breastbone."
        case .midSternum:
            return "Upright, centred halfway along the breastbone, camera end towards your chin."
        case .diaphragm:
            return "Phone centred just BELOW the bottom tip of the breastbone, on the soft area where the ribs part. Upright or sideways (long side across the body), whichever lies flatter. Keep it flat and still, press lightly. For women this sits below the bra band."
        }
    }
    /// Sites that can alternate with the lower breastbone.
    static var testSites: [BodyPlacement] { allCases.filter { $0 != .sternum } }
}

/// Get-ready checklist item (information only: saved with the recording, never blocks it).
struct ChecklistItem: Identifiable {
    let key: String
    let text: String
    var id: String { key }

    static func items(for mode: Mode) -> [ChecklistItem] {
        let dnd = ChecklistItem(key: "do_not_disturb", text: "Do Not Disturb on, no calls allowed")
        let finger = ChecklistItem(key: "finger_light_press", text: "Fingertip covers camera and flash, light steady press")
        guard mode == .chest else { return [dnd, finger] }
        return [dnd,
                ChecklistItem(key: "rested_seated", text: "Rested 5 min, back supported, feet flat, legs uncrossed"),
                ChecklistItem(key: "hands_warm", text: "Hands warm"),
                finger]
    }
}

enum StartMethod: String, CaseIterable, Identifiable {
    case doubleTap, countdown
    var id: String { rawValue }
    var title: String { self == .doubleTap ? "Double tap the phone" : "Countdown" }
}

enum Phase { case idle, preparing, recording, saving, done }

struct LiveStats {
    var fps = 0.0, accHz = 0.0
    var r: Float = 0, g: Float = 0, b: Float = 0
    var sat: Float = 0, iso: Float = 0, expMs: Float = 0
    var ppg: [Double] = []          // finger pulse, filtered 0.5-10 Hz, last 4 s
    var scg: [Double] = []          // chest, out of the chest, filtered 5-40 Hz, last 4 s
    var beat = LiveBeat()           // heart rate + chest beat average
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
    /// 45 = adaptive for chest recordings: 45 s, carried on to 60 s automatically if the recording isn't Good yet.
    @Published var duration = 45
    @Published var accHz = 400
    /// Remembered between app launches, so every recording on this phone uses the same lens.
    @Published var lens: CameraLens = CameraLens.remembered() {
        didSet { UserDefaults.standard.set(lens.rawValue, forKey: "hc.lens") }
    }
    @Published var placement: BodyPlacement = .sternum
    /// Site test (0.4.2): switch between the test site and the lower breastbone after each chest recording.
    /// Turning it on starts with the test site.
    @Published var placementTest = false {
        didSet { if placementTest && !oldValue { placement = testSite } }
    }
    /// The site that alternates with the lower breastbone (never the breastbone itself).
    @Published var testSite: BodyPlacement = .sternumSideways {
        didSet { if placementTest && testSite != oldValue { placement = testSite } }
    }
    /// Get-ready checklist, saved with the recording (information only).
    @Published var checklist: [String: Bool] = [:]
    /// Recording clock for the screen, whole seconds.
    @Published var elapsedS = 0
    @Published var targetS = 45
    /// The last recording, for the result screen.
    @Published var lastLengthS = 0
    @Published var lastTime = ""
    @Published var startMethod: StartMethod = StartMethod(rawValue: UserDefaults.standard.string(forKey: "hc.start") ?? "") ?? .doubleTap {
        didSet { UserDefaults.standard.set(startMethod.rawValue, forKey: "hc.start") }
    }
    /// Flash starts at 70% every recording and is raised (80%, 90%, 100%) only while positioning, and only if
    /// the finger is too dim with the camera already at its most sensitive. It never changes during the recording.
    let torchStartPct = 70
    @Published var torchNowPct = 70
    @Published var colourChannel: String? = ColourProfile.channel
    @Published var colourMessage = ""
    @Published var settle = 10
    @Published var prepStatus = ""
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
    var usesDoubleTap: Bool { mode == .chest && startMethod == .doubleTap }
    let doubleTapTimeout = 60.0
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
    // positioning (double tap)
    private var readySince: Double?
    private var startPendingAt: Double?
    private var lastSpeaking = 0.0
    private var lastTipAt = 0.0
    private var lastTip = ""
    private var gravityAtStart: [Double] = []
    private var recordPlacement: BodyPlacement = .sternum
    private var recordPlacementTest = false
    private var recordTestSite: BodyPlacement = .sternumSideways
    private var recordStart = StartMethod.countdown
    // adaptive length
    private var adaptiveLength = false
    private var lengthDecided = true
    private var targetLength = 45.0
    private var gradeRunning = false
    private var extended = false
    private var quickGrade: Grade?
    private var finishing = false
    private var cancelling = false

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
        readySince = nil; startPendingAt = nil; lastSpeaking = 0; lastTipAt = 0; lastTip = ""; gravityAtStart = []
        adaptiveLength = false; lengthDecided = true; gradeRunning = false; extended = false; quickGrade = nil
        finishing = false
        cancelling = false
        recordPlacement = placement
        recordPlacementTest = placementTest
        recordTestSite = testSite
        checklist = [:]
        elapsedS = 0
        targetS = duration
        recordStart = usesDoubleTap ? .doubleTap : .countdown
        analysis = nil; analysisError = nil; analyzing = false
        cuffSBP = ""; cuffDBP = ""; notes = ""; savedNote = ""
        UIApplication.shared.isIdleTimerDisabled = true
        // screen goes dark and ignores touches while it is against the chest (or face-down on the table)
        UIDevice.current.isProximityMonitoringEnabled = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        switch mode {
        case .table:
            speak("Place your finger on the camera, check the light bar, then lay the phone screen down.")
        case .tap:
            speak("Place your finger, check the light bar, then put the phone on your chest.")
        case .chest:
            let whereTo = "\(placement.turnName) \(placement.spokenWhere)"
            speak(usesDoubleTap
                  ? "Place your finger and check the light bar. Then put the phone \(whereTo), and double tap it when you're ready."
                  : "Place your finger, check the light bar, then put the phone \(whereTo).")
        }
        prepStatus = "Place your finger on the camera and check the light bar."
        phase = .preparing
        remaining = usesDoubleTap ? Int(doubleTapTimeout) : Int(settleSeconds)
        await camera.start()
        motion.start(hz: Double(accHz))
        tStart = HostClock.now
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = HostClock.now
        if speech.isSpeaking { lastSpeaking = now }
        switch phase {
        case .preparing:
            if cancelling { break }
            raiseFlashIfDim(now)
            if usesDoubleTap {
                prepareDoubleTap(now)
            } else {
                let left = settleSeconds - (now - tStart)
                remaining = max(0, Int(left.rounded(.up)))
                if left <= 0 { beginRecording() }
            }
        case .recording:
            let el = now - tRecord
            if adaptiveLength && !lengthDecided {
                if el >= 45 && !gradeRunning { runQuickGrade() }
                if el >= 60 {
                    lengthDecided = true
                    targetLength = 60
                    extended = true
                }
            }
            remaining = max(0, Int((targetLength - el).rounded(.up)))
            let shownElapsed = min(Int(el), Int(targetLength)), shownTarget = Int(targetLength)
            if shownElapsed != elapsedS { elapsedS = shownElapsed }
            if shownTarget != targetS { targetS = shownTarget }
            if el >= targetLength && lengthDecided && !finishing {
                finishing = true
                Task { await finish() }
            }
        default:
            break
        }
        updateLive()
    }

    // MARK: positioning

    private func fingerPresent() -> Bool {
        let rp = camera.recent(seconds: 1.0)
        guard rp.count > 10 else { return false }
        var r = 0.0, g = 0.0
        for p in rp { r += Double(p.r); g += Double(p.g) }
        r /= Double(rp.count); g /= Double(rp.count)
        return r > 20 && r > 1.8 * g
    }

    private struct Pose {
        var upright = false, sideways = false, onChest = false
        var g = (x: 0.0, y: 0.0, z: 0.0)
    }

    /// The turn each site expects (0.4.2; same table as the laptop site-test rules v1).
    private func placedOK(_ p: Pose) -> Bool {
        (recordPlacement.allowsUpright && p.upright)
            || (recordPlacement.allowsSideways && p.sideways && abs(p.g.y) < 0.5)
    }

    private static func orientationName(_ g: [Double]) -> String {
        guard g.count == 3 else { return "unknown" }
        if g[1] < -0.6 && abs(g[0]) < 0.5 { return "upright" }
        if abs(g[0]) >= 0.6 && abs(g[1]) < 0.5 { return "sideways" }
        return "other"
    }

    private func pose() -> Pose {
        var p = Pose()
        let a = motion.recentAcc(seconds: 1.0)
        guard a.count > 20 else { return p }
        p.g = LiveDSP.gravity(a)
        p.upright = p.g.y < -0.6 && abs(p.g.x) < 0.5
        p.sideways = abs(p.g.x) >= 0.6
        // screen facing the chest: the proximity sensor is covered, or the screen is tilted towards the body
        p.onChest = UIDevice.current.proximityState || p.g.z > -0.05
        return p
    }

    /// Raise the flash one step (max 100%) if the finger is dim and the camera can't brighten any more by itself.
    private func raiseFlashIfDim(_ now: Double) {
        guard startPendingAt == nil, now - tStart > 3, now - lastTorchStep > 2, torchNowPct < 100 else { return }
        if !usesDoubleTap && settleSeconds - (now - tStart) <= 1.5 { return }
        let light = recentLight(1.0)
        if fingerPresent() && light > 0 && light < 150 && camera.atSensitivityLimit {
            torchNowPct = min(100, torchNowPct + 10)
            camera.setTorch(level: Double(torchNowPct) / 100)
            lastTorchStep = now
        }
    }

    private func prepareDoubleTap(_ now: Double) {
        let waited = now - tStart
        remaining = max(0, Int((doubleTapTimeout - waited).rounded(.up)))
        if let sp = startPendingAt {
            prepStatus = "Starting… stay still."
            if now - sp >= 3.0 && !speech.isSpeaking { beginRecording() }
            return
        }
        if waited > doubleTapTimeout {
            cancelling = true
            Task { await cancelPreparing("No double tap within a minute. Stopped, flash off.") }
            return
        }
        let p = pose()
        let finger = fingerPresent()
        let still = LiveDSP.shake(motion.recentAcc(seconds: 1.5)) < 0.05
        if p.onChest && placedOK(p) && finger {
            if readySince == nil && still {
                readySince = now
                speakTip("Phone in place. Hold still. Double tap the phone when you're ready.", now)
            }
        } else {
            readySince = nil
        }
        if !finger {
            prepStatus = "Cover the camera and the flash with your fingertip."
        } else if !p.onChest {
            prepStatus = "Finger OK. Now put the phone on your chest, screen against you."
        } else if !placedOK(p) {
            prepStatus = recordPlacement.turnTip
        } else {
            prepStatus = readySince == nil ? "Hold still…" : "In place. Double tap the phone to start."
        }
        // spoken tips every 8 s (a changed tip) or 16 s (the same tip); none while speaking
        if !speech.isSpeaking && now - lastSpeaking > 0.5 && now - lastTipAt >= 8 && waited > 6 {
            if let tip = positioningTip(p, finger: finger, now: now), tip != lastTip || now - lastTipAt >= 16 {
                speakTip(tip, now)
            }
        }
        // double tap: only once in place, and not right after the app has spoken (speech shakes the phone)
        if let rs = readySince, now - rs >= 1.0, !speech.isSpeaking, now - lastSpeaking > 0.4 {
            if LiveDSP.doubleTap(motion.recentAcc(seconds: 2.0), after: max(rs, lastSpeaking + 0.4)) != nil {
                startPendingAt = now
                speak("Starting in 3 seconds. Stay still.")
                lastSpeaking = now
            }
        }
    }

    private func positioningTip(_ p: Pose, finger: Bool, now: Double) -> String? {
        if !finger { return "Cover the camera and the flash with your fingertip." }
        if !p.onChest { return nil }
        if !placedOK(p) { return recordPlacement.turnTip }
        guard let rs = readySince, now - rs >= 8 else { return nil }
        let l = slow.lock
        guard l.isFinite else { return nil }
        if l > 6 { return "Heartbeat clear. Double tap when ready." }
        return (l > 3 ? "Heartbeat weak. " : "No heartbeat yet. ") + recordPlacement.weakTip
    }

    private func speakTip(_ text: String, _ now: Double) {
        speak(text)
        lastTip = text
        lastTipAt = now
        lastSpeaking = now
    }

    private func beginRecording() {
        checkLightAtStart()
        let p = pose()
        gravityAtStart = [p.g.x, p.g.y, p.g.z]
        if mode == .chest && !placedOK(p) {
            flags.append("Phone not \(recordPlacement.turnName) when recording started (\(recordPlacement.name), "
                         + String(format: "gravity x %+.2f, y %+.2f). ", p.g.x, p.g.y) + recordPlacement.turnTip)
        }
        camera.freezeExposure()
        tRecord = HostClock.now
        adaptiveLength = mode == .chest && duration == 45
        targetLength = Double(duration)
        lengthDecided = !adaptiveLength
        prepStatus = ""
        phase = .recording
        // haptic only, no sound: the speaker would shake the accelerometer
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// At 45 s: grade what has been recorded with the fixed method; Good -> stop, otherwise carry on to 60 s.
    private func runQuickGrade() {
        gradeRunning = true
        let tr = tRecord
        let p = camera.recent(seconds: 70).filter { $0.t >= tr }
        let a = motion.recentAcc(seconds: 70).filter { $0.t >= tr }
        let ch = ColourProfile.channel
        Task {
            let g = await Task.detached(priority: .userInitiated) { Analyzer.quickGrade(ppg: p, acc: a, channel: ch) }.value
            self.quickGrade = g
            guard self.phase == .recording, !self.lengthDecided else { return }
            self.lengthDecided = true
            if g.good {
                self.targetLength = max(45, HostClock.now - self.tRecord)
            } else {
                self.targetLength = 60
                self.extended = true
            }
        }
    }

    private func cancelPreparing(_ reason: String) async {
        guard phase == .preparing else { return }
        timer?.invalidate(); timer = nil
        motion.stop()
        await camera.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.isProximityMonitoringEnabled = false
        prepStatus = ""
        phase = .idle
        errorMessage = reason
        speak(reason)
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
            // while positioning, only use the time since the phone has been in place
            var w = 20.0
            if phase == .preparing, let rs = readySince { w = min(20, max(7, now - rs)) }
            slow = LiveDSP.beatSummary(ppg: camera.recent(seconds: w), acc: motion.recentAcc(seconds: w),
                                       channel: ColourProfile.channel)
            liveChannel = slow.channel
        }
        s.beat = slow
        live = s
    }

    func mark() { markers.append((HostClock.now, "mark")) }

    func toggleCheck(_ key: String) { checklist[key] = !(checklist[key] ?? false) }

    private func checklistMeta() -> [String: Bool] {
        var m: [String: Bool] = [:]
        for item in ChecklistItem.items(for: mode) { m[item.key] = checklist[item.key] ?? false }
        return m
    }

    /// t = moment the press started (the button needs a hold, so the mark is back-dated to the press).
    func mark(at t: Double) { markers.append((t, "mark")) }

    func stopEarly() {
        if phase == .preparing {
            guard !cancelling else { return }
            cancelling = true
            Task { await cancelPreparing("Stopped before recording started.") }
            return
        }
        guard phase == .recording, !finishing else { return }
        finishing = true
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
        var qg: [String: Any] = [:]
        if let g = quickGrade {
            qg["good"] = g.good
            qg["reasons"] = g.reasons
            if g.pttMedianMs.isFinite { qg["ptt_ms"] = g.pttMedianMs }
            if g.pttSpreadMs.isFinite { qg["spread_ms"] = g.pttSpreadMs }
        }
        let placementValue: Any = mode == .chest ? recordPlacement.rawValue : NSNull()
        let testSiteValue: Any = (mode == .chest && recordPlacementTest) ? recordTestSite.rawValue : NSNull()
        let turnValue: Any = mode == .chest ? recordPlacement.turnName : NSNull()
        lastLengthS = Int((tEnd - tRecord).rounded())
        let hm = DateFormatter()
        hm.dateFormat = "HH:mm"
        lastTime = hm.string(from: Date())
        let quickValue: Any = qg.isEmpty ? NSNull() : qg
        meta = [
            "app": "HC Capture \(AppInfo.version)",
            "analysis_version": 2.2,
            "lens": lens.rawValue,
            "created_local": iso8601.string(from: Date()),
            "device_model": SessionStore.modelIdentifier,
            "os_version": UIDevice.current.systemVersion,
            "mode": mode.rawValue,
            "placement": placementValue,
            "placement_test": mode == .chest && recordPlacementTest,
            "placement_test_site": testSiteValue,
            "placement_turn": turnValue,
            "checklist": checklistMeta(),
            "start_method": recordStart.rawValue,
            "fps_target": fps,
            "acc_rate_requested_hz": accHz,
            "duration_target_s": duration,
            "length_rule": adaptiveLength ? "45 s, carried on to 60 s if not Good at 45 s" : "fixed",
            "extended": extended,
            "quick_grade_45s": quickValue,
            "settle_s": settleSeconds,
            "record_start_t": tRecord,
            "record_end_t": tEnd,
            "clock": "host clock seconds (mach time); camera PTS converted from session sync clock; CoreMotion timestamps",
            "camera": cameraInfo,
            "dropped_frames": dropped,
            "units": ["acc": "g", "gyro": "rad/s", "ppg": "mean 0-255 per channel"],
            "orientation_protocol": mode == .table ? "screen down on table"
                : "screen against chest, turned as the site expects (placement_turn); iOS reports minus the acceleration, so +z = out of chest",
            "gravity_at_start": gravityAtStart,
            "orientation": mode == .table ? "screen down" : Recorder.orientationName(gravityAtStart),
            "tilt": tiltInfo(gravityAtStart),
            "cuff_sbp": NSNull(), "cuff_dbp": NSNull(), "notes": "",
            "torch_level_start": Double(torchStartPct) / 100,
            "flash_raised": torchNowPct > torchStartPct,
            "torch_level_record": Double(torchNowPct) / 100,
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
        if mode == .chest && placementTest {
            placement = recordPlacement == .sternum ? testSite : .sternum
        }
        phase = .done
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        speak("Done.")
        runAnalysis(folder)
    }

    /// Phone angle at the start of the recording, from gravity (reported only).
    /// screen_from_vertical_deg: 0 = screen vertical, 90 = phone flat. roll_deg: 0 = upright, +-90 = sideways.
    private func tiltInfo(_ g: [Double]) -> Any {
        guard g.count == 3 else { return NSNull() }
        let n = sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2])
        guard n > 0.5 else { return NSNull() }
        let screen = asin(min(1, abs(g[2]) / n)) * 180 / .pi
        let roll = atan2(g[0], -g[1]) * 180 / .pi
        return ["screen_from_vertical_deg": screen, "roll_deg": roll]
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
        if r.mode == "chest" && placementTest {
            post += " Next placement: \(placement.title)."
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
            return parts.joined(separator: " ")
        }
        if let g = r.grade {
            if g.good {
                parts.append("Recording good.")
            } else {
                parts.append("Recording weak: \(g.reasons.first ?? "see the screen").")
            }
        } else if !b.isFinite {
            parts.append("Not enough beats for the heartbeat check.")
        } else if b > 6 {
            parts.append("Heartbeat clear in the chest signal.")
        } else {
            parts.append("Heartbeat weak in the chest signal.")
        }
        return parts.joined(separator: " ")
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        speech.speak(u)
    }
}
