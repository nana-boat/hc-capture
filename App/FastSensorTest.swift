import AVFoundation
import CoreMotion
import SwiftUI
import UIKit

// HC Capture 0.4.1: fast motion-data test (PLAN_HCCapture_0.4.1.md, section A).
// Question: does this iPhone give an app motion data faster than about 100 samples a second?
// Phone still on a table. No HealthKit and no workout session. Rules were set before the test:
//   rate from the timestamps (not the number of deliveries); PASS = median rate above 150 per second AND
//   longest step no more than 3 times the median step. The fast "device motion" rotation rate is a processed
//   signal, not the raw gyro: it is reported, never used in place of gyro.csv.

/// One timestamped 3-axis sample and the number of the delivery (batch) it arrived in.
struct TestSample {
    var t: Double
    var x: Double
    var y: Double
    var z: Double
    var batch: Int
}

/// Thread-safe store for one stream (Core Motion calls back on its own threads).
final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [TestSample] = []
    private var nBatches = 0
    private var errorText: String?

    func newBatch() -> Int {
        lock.lock(); defer { lock.unlock() }
        nBatches += 1
        return nBatches
    }
    func append(_ s: TestSample) { lock.lock(); rows.append(s); lock.unlock() }
    func append(contentsOf s: [TestSample]) { lock.lock(); rows.append(contentsOf: s); lock.unlock() }
    func fail(_ e: Error) {
        lock.lock()
        if errorText == nil { errorText = e.localizedDescription }
        lock.unlock()
    }
    func snapshot() -> (rows: [TestSample], batches: Int, error: String?) {
        lock.lock(); defer { lock.unlock() }
        return (rows, nBatches, errorText)
    }
}

/// JSON can't hold NaN: write null instead.
private func jnum(_ v: Double) -> Any { v.isFinite ? v : NSNull() }

struct StreamStats {
    var name: String
    var samples = 0
    var batches = 0
    var seconds = Double.nan
    var medianStepMs = Double.nan
    var medianRateHz = Double.nan
    var meanRateHz = Double.nan
    var maxStepMs = Double.nan
    var stepsOver3x = 0
    var sameTime = 0
    var repeats = 0
    var maxBatchEdgeStepMs = Double.nan
    var error: String?

    var pass: Bool {
        medianRateHz.isFinite && medianRateHz > 150 && maxStepMs.isFinite && maxStepMs <= 3 * medianStepMs
    }

    static func from(_ name: String, _ box: SampleBox) -> StreamStats {
        let snap = box.snapshot()
        var st = StreamStats(name: name)
        st.batches = snap.batches
        st.error = snap.error
        let r = snap.rows.sorted { $0.t < $1.t }
        st.samples = r.count
        guard r.count >= 3 else { return st }
        var steps: [Double] = []
        steps.reserveCapacity(r.count)
        var edge = 0.0
        var sawEdge = false
        for i in 1..<r.count {
            let d = r[i].t - r[i - 1].t
            steps.append(d)
            if d <= 0 { st.sameTime += 1 }
            if r[i].batch != r[i - 1].batch { edge = max(edge, d); sawEdge = true }
            if r[i].x == r[i - 1].x && r[i].y == r[i - 1].y && r[i].z == r[i - 1].z { st.repeats += 1 }
        }
        let med = DSP.median(steps)
        st.seconds = r[r.count - 1].t - r[0].t
        st.medianStepMs = med * 1000
        st.medianRateHz = med > 0 ? 1 / med : .nan
        st.meanRateHz = st.seconds > 0 ? Double(r.count - 1) / st.seconds : .nan
        st.maxStepMs = (steps.max() ?? .nan) * 1000
        st.stepsOver3x = steps.filter { $0 > 3 * med }.count
        st.maxBatchEdgeStepMs = sawEdge ? edge * 1000 : .nan
        return st
    }

    var dict: [String: Any] {
        var d: [String: Any] = [
            "stream": name, "samples": samples, "deliveries": batches, "span_s": jnum(seconds),
            "median_step_ms": jnum(medianStepMs), "median_rate_hz": jnum(medianRateHz), "mean_rate_hz": jnum(meanRateHz),
            "max_step_ms": jnum(maxStepMs), "steps_over_3x_median": stepsOver3x, "zero_or_negative_steps": sameTime,
            "repeated_identical_samples": repeats, "max_step_at_delivery_edge_ms": jnum(maxBatchEdgeStepMs),
            "pass": pass,
        ]
        if let e = error { d["error"] = e }
        return d
    }

    var line: String {
        if samples < 3 { return "\(name): no data" + (error.map { " (\($0))" } ?? "") }
        return "\(name): \(fmt(medianRateHz, "%.1f"))/s (median), longest step \(fmt(maxStepMs, "%.1f")) ms, "
            + "\(samples) samples in \(batches) deliveries -> " + (pass ? "PASS" : "no")
    }
}

@MainActor
final class FastSensorTest: ObservableObject {
    @Published var running = false
    @Published var status = "Not run yet."
    @Published var lines: [String] = []
    @Published var folder: URL?
    @Published var shareItem: ShareItem?

    let runSeconds = 20.0
    private let camera = CameraPPG()
    private var summary: [String: Any] = [:]
    private var runs: [[String: Any]] = []
    private var fastPass: [Bool] = []

    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SensorTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// What the fast (batched) interface says about itself.
    func batchedSupport() -> [String: Any] {
        if #available(iOS 17.0, *) {
            return [
                "interface_present": true,
                "accelerometer_supported": CMBatchedSensorManager.isAccelerometerSupported,
                "device_motion_supported": CMBatchedSensorManager.isDeviceMotionSupported,
                "authorization_status": CMBatchedSensorManager.authorizationStatus.rawValue,
                "authorization_note": "0 not determined, 1 restricted, 2 denied, 3 authorized",
            ]
        }
        return ["interface_present": false]
    }

    func start() async {
        guard !running else { return }
        running = true
        lines = []
        runs = []
        fastPass = []
        UIApplication.shared.isIdleTimerDisabled = true
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let dir = FastSensorTest.root.appendingPathComponent("fastdata_\(f.string(from: Date()))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        folder = dir
        let support = batchedSupport()
        summary = [
            "test": "fast motion-data test (0.4.1 plan, section A)",
            "app": "HC Capture 0.4.1",
            "device_model": SessionStore.modelIdentifier,
            "os_version": UIDevice.current.systemVersion,
            "created_local": ISO8601DateFormatter().string(from: Date()),
            "run_seconds": runSeconds,
            "rule": "PASS = median rate above 150 per second AND longest step at most 3 x the median step; rate from timestamps",
            "fast_interface": support,
            "thermal_state_start": FastSensorTest.thermal(),
        ]
        save(dir)
        lines.append("Fast interface: " + describe(support))

        await runNormal(dir, label: "a. normal interface (reference)")
        let accOK = (support["accelerometer_supported"] as? Bool) ?? false
        let dmOK = (support["device_motion_supported"] as? Bool) ?? false
        if accOK || dmOK {
            await runFast(dir, label: "b. fast interface, camera and flash off", useCamera: false, alsoNormal: false)
            await runFast(dir, label: "c. fast interface, camera and flash on", useCamera: true, alsoNormal: false)
            await runFast(dir, label: "d. normal and fast interfaces together", useCamera: false, alsoNormal: true)
        } else {
            lines.append("b-d skipped: the phone says the fast interface is not supported.")
        }
        let verdict = fastPass.contains(true)
            ? "YES: fast motion data reached the pass mark in at least one run. Next: tap test on the fast data."
            : "NO: no run reached the pass mark. Plan for about 100 per second (workout-session route = 0.4.2)."
        summary["verdict"] = verdict
        summary["thermal_state_end"] = FastSensorTest.thermal()
        lines.append(verdict)
        save(dir)
        status = "Done. Saved in Files > On My iPhone > HC Capture > SensorTests."
        UIApplication.shared.isIdleTimerDisabled = false
        running = false
    }

    private func describe(_ s: [String: Any]) -> String {
        guard (s["interface_present"] as? Bool) == true else { return "not on this iOS version" }
        let a = (s["accelerometer_supported"] as? Bool) == true ? "yes" : "no"
        let d = (s["device_motion_supported"] as? Bool) == true ? "yes" : "no"
        let code = (s["authorization_status"] as? Int).map { String($0) } ?? "?"
        return "accelerometer \(a), device motion \(d), permission code \(code)"
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func normalManager(_ acc: SampleBox, _ gyro: SampleBox) -> CMMotionManager {
        let mm = CMMotionManager()
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        mm.accelerometerUpdateInterval = 1.0 / 400
        mm.gyroUpdateInterval = 1.0 / 400
        mm.startAccelerometerUpdates(to: q) { data, err in
            if let e = err { acc.fail(e) }
            guard let d = data else { return }
            acc.append(TestSample(t: d.timestamp, x: d.acceleration.x, y: d.acceleration.y, z: d.acceleration.z, batch: 0))
        }
        if mm.isGyroAvailable {
            mm.startGyroUpdates(to: q) { data, err in
                if let e = err { gyro.fail(e) }
                guard let d = data else { return }
                gyro.append(TestSample(t: d.timestamp, x: d.rotationRate.x, y: d.rotationRate.y, z: d.rotationRate.z, batch: 0))
            }
        }
        return mm
    }

    private func runNormal(_ dir: URL, label: String) async {
        status = "Running \(label) for \(Int(runSeconds)) s. Keep the phone still."
        let thermalBefore = FastSensorTest.thermal()
        let acc = SampleBox(), gyro = SampleBox()
        let mm = normalManager(acc, gyro)
        await wait(runSeconds)
        mm.stopAccelerometerUpdates()
        mm.stopGyroUpdates()
        let stats = [StreamStats.from("normal accelerometer", acc), StreamStats.from("normal gyro", gyro)]
        record(dir, label: label, stats: stats, boxes: [("a_normal_acc.csv", acc), ("a_normal_gyro.csv", gyro)],
               extra: ["requested_hz": 400, "thermal_before": thermalBefore])
    }

    private func runFast(_ dir: URL, label: String, useCamera: Bool, alsoNormal: Bool) async {
        guard #available(iOS 17.0, *) else { return }
        let key = String(label.prefix(1))
        summary["about_to_run"] = label          // stays in the file if the app crashes during this run
        save(dir)
        status = "Running \(label) for \(Int(runSeconds)) s. Keep the phone still."
        let thermalBefore = FastSensorTest.thermal()
        var extra: [String: Any] = ["thermal_before": thermalBefore]
        if useCamera {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                lines.append("\(label): skipped, camera permission is off.")
                return
            }
            do {
                let info = try camera.configure(targetFPS: 120, lens: CameraLens.remembered(), torchLevel: 0.7)
                extra["camera"] = info
            } catch {
                lines.append("\(label): skipped, camera error: \(error.localizedDescription)")
                return
            }
            await camera.start()
            await wait(1.0)
        }
        let acc = SampleBox(), rot = SampleBox(), nAcc = SampleBox(), nGyro = SampleBox()
        let bm = CMBatchedSensorManager()
        extra["accelerometer_data_frequency"] = bm.accelerometerDataFrequency
        extra["device_motion_data_frequency"] = bm.deviceMotionDataFrequency
        if CMBatchedSensorManager.isAccelerometerSupported {
            bm.startAccelerometerUpdates { batch, err in
                if let e = err { acc.fail(e) }
                let b: [CMAccelerometerData] = batch ?? []
                if b.isEmpty { return }
                let k = acc.newBatch()
                acc.append(contentsOf: b.map {
                    TestSample(t: $0.timestamp, x: $0.acceleration.x, y: $0.acceleration.y, z: $0.acceleration.z, batch: k)
                })
            }
        }
        if CMBatchedSensorManager.isDeviceMotionSupported {
            bm.startDeviceMotionUpdates { batch, err in
                if let e = err { rot.fail(e) }
                let b: [CMDeviceMotion] = batch ?? []
                if b.isEmpty { return }
                let k = rot.newBatch()
                rot.append(contentsOf: b.map {
                    TestSample(t: $0.timestamp, x: $0.rotationRate.x, y: $0.rotationRate.y, z: $0.rotationRate.z, batch: k)
                })
            }
        }
        var mm: CMMotionManager?
        if alsoNormal { mm = normalManager(nAcc, nGyro) }
        await wait(runSeconds)
        bm.stopAccelerometerUpdates()
        bm.stopDeviceMotionUpdates()
        mm?.stopAccelerometerUpdates()
        mm?.stopGyroUpdates()
        if useCamera {
            let (frames, dropped) = camera.takeAll()
            await camera.stop()
            if frames.count > 2, let a = frames.first?.t, let b = frames.last?.t, b > a {
                extra["camera_fps_measured"] = Double(frames.count - 1) / (b - a)
            }
            extra["camera_dropped_frames"] = dropped
        }
        var stats = [StreamStats.from("fast accelerometer", acc),
                     StreamStats.from("fast device-motion rotation (processed, not raw gyro)", rot)]
        var boxes: [(String, SampleBox)] = [("\(key)_fast_acc.csv", acc), ("\(key)_fast_devicemotion_rotation.csv", rot)]
        if alsoNormal {
            stats += [StreamStats.from("normal accelerometer (same time)", nAcc), StreamStats.from("normal gyro (same time)", nGyro)]
            boxes += [("\(key)_normal_acc.csv", nAcc), ("\(key)_normal_gyro.csv", nGyro)]
        }
        fastPass.append(stats[0].pass)
        summary["about_to_run"] = nil
        record(dir, label: label, stats: stats, boxes: boxes, extra: extra)
    }

    private func record(_ dir: URL, label: String, stats: [StreamStats], boxes: [(String, SampleBox)],
                        extra: [String: Any]) {
        var run: [String: Any] = ["run": label, "streams": stats.map { $0.dict }, "thermal_after": FastSensorTest.thermal()]
        for (k, v) in extra { run[k] = v }
        runs.append(run)
        summary["runs"] = runs
        for (name, box) in boxes { writeCSV(dir.appendingPathComponent(name), box) }
        lines.append(label)
        lines += stats.map { "   " + $0.line }
        save(dir)
    }

    private func writeCSV(_ url: URL, _ box: SampleBox) {
        let rows = box.snapshot().rows
        var s = "t,x,y,z,delivery\n"
        s.reserveCapacity(rows.count * 64)
        for r in rows { s += String(format: "%.6f,%.6f,%.6f,%.6f,%d\n", r.t, r.x, r.y, r.z, r.batch) }
        try? s.write(to: url, atomically: true, encoding: .utf8)
    }

    private func save(_ dir: URL) {
        if JSONSerialization.isValidJSONObject(summary),
           let d = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: dir.appendingPathComponent("summary.json"))
        }
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    func share() {
        guard let f = folder, let z = try? SessionStore.zip(f) else { return }
        shareItem = ShareItem(url: z)
    }
}

struct FastSensorTestView: View {
    @StateObject private var test = FastSensorTest()

    var body: some View {
        Form {
            Section {
                Text("Checks whether this iPhone gives the app motion data faster than about 100 samples a second. "
                     + "Lay the phone flat on a table and don't touch it. Four runs of 20 s (about 2 minutes); "
                     + "in one of them the flash comes on. Nothing is sent anywhere.")
                    .font(.callout)
            }
            Section {
                Button {
                    Task { await test.start() }
                } label: {
                    Text(test.running ? "Running…" : "Start test").frame(maxWidth: .infinity).font(.headline)
                }
                .disabled(test.running)
                Text(test.status).font(.caption).foregroundColor(.secondary)
            }
            if !test.lines.isEmpty {
                Section("Results") {
                    ForEach(Array(test.lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(.caption.monospaced())
                    }
                }
            }
            if test.folder != nil && !test.running {
                Section {
                    Button("Share test results (zip)") { test.share() }
                }
            }
        }
        .navigationTitle("Fast motion-data test")
        .sheet(item: $test.shareItem) { item in ActivityView(items: [item.url]) }
    }
}
