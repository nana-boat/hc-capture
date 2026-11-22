import SwiftUI
import UIKit

@main
struct HCCaptureApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var rec = Recorder()

    var body: some View {
        NavigationStack {
            Group {
                switch rec.phase {
                case .idle: SetupView(rec: rec)
                case .preparing, .recording, .saving: RunView(rec: rec)
                case .done: ResultView(rec: rec)
                }
            }
            .navigationTitle("HC Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $rec.shareItem) { item in ActivityView(items: [item.url]) }
    }
}

struct SetupView: View {
    @ObservedObject var rec: Recorder

    var body: some View {
        Form {
            Section {
                Text("Research prototype. Not a medical device. This app records and analyses signals only and shows no blood pressure.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("Recording type") {
                Picker("Mode", selection: $rec.mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(rec.mode.instructions).font(.callout)
            }
            Section("Camera") {
                LensChooser(rec: rec)
                HStack {
                    Text("Flash")
                    Spacer()
                    Text("starts at \(rec.torchStartPct)%, automatic").foregroundColor(.secondary)
                }
                Text("If your finger is too dim while you position it, the flash is raised automatically (up to 100%). It never changes during the recording.")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Text("Finger colour")
                    Spacer()
                    Text(rec.colourChannel == nil ? "automatic, not chosen yet" : "\(ColourProfile.name(rec.colourChannel)), chosen automatically")
                        .foregroundColor(.secondary)
                }
                Text(rec.colourChannel == nil
                     ? "Chosen automatically on your first chest or table recording with a clean pulse, then kept for every recording."
                     : "Kept for every recording. Chosen again automatically only if it fails 3 recordings in a row.")
                    .font(.caption).foregroundColor(.secondary)
                if rec.colourChannel != nil {
                    Button("Choose finger colour again (new person on this phone)") { rec.resetColour() }
                        .font(.callout)
                }
                if !rec.colourMessage.isEmpty {
                    Text(rec.colourMessage).font(.caption).foregroundColor(.orange)
                }
                Picker("Positioning time", selection: $rec.settle) {
                    ForEach([7, 10, 15], id: \.self) { Text("\($0) s").tag($0) }
                }
            }
            Section("Settings") {
                Picker("Camera frame rate", selection: $rec.fps) {
                    ForEach([60, 120, 240], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Recording length", selection: $rec.duration) {
                    ForEach([30, 60, 90], id: \.self) { Text("\($0) s").tag($0) }
                }
                Picker("Accelerometer request", selection: $rec.accHz) {
                    ForEach([100, 200, 400], id: \.self) { Text("\($0) Hz").tag($0) }
                }
                Text("iPhones often cap the accelerometer near 100 Hz. The real rate is measured and saved.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let e = rec.errorMessage {
                Section { Text(e).foregroundColor(.red) }
            }
            Section {
                Button {
                    Task { await rec.start() }
                } label: {
                    Text("Start").frame(maxWidth: .infinity).font(.headline)
                }
            }
            Section("Recordings (also in Files > On My iPhone > HC Capture)") {
                if rec.recordings.isEmpty {
                    Text("None yet").foregroundColor(.secondary)
                }
                ForEach(rec.recordings, id: \.self) { url in
                    NavigationLink(destination: SessionDetailView(rec: rec, folder: url)) {
                        Label(url.lastPathComponent, systemImage: "waveform.path.ecg")
                    }
                }
                .onDelete { rec.delete(at: $0) }
                if !rec.recordings.isEmpty {
                    NavigationLink(destination: CompareView(rec: rec)) {
                        Label("Compare sessions", systemImage: "chart.bar.xaxis")
                    }
                    Button("Share all recordings (zip)") { rec.shareAll() }
                }
            }
        }
    }
}

struct RunView: View {
    @ObservedObject var rec: Recorder

    var title: String {
        switch rec.phase {
        case .preparing: return "Place your finger and check the light bar. Camera is adjusting."
        case .recording: return "Recording. Stay still."
        default: return "Saving…"
        }
    }

    var hrText: String { rec.live.beat.hr.isFinite ? String(format: "%.0f bpm", rec.live.beat.hr) : "– bpm" }

    var lockText: String {
        let b = rec.live.beat
        let prefix = rec.mode == .table ? "Finger pulse in accelerometer: " : "Heartbeat in chest signal: "
        guard b.lock.isFinite else { return prefix + "collecting beats…" }
        let r = String(format: "%.1f", b.lock)
        if rec.mode == .table {
            return prefix + (b.lock > 3 ? "leaking in" : "none") + " (ratio \(r), \(b.n) beats)"
        }
        let v = b.lock > 6 ? "clear" : (b.lock > 3 ? "weak" : "not yet")
        return prefix + v + " (ratio \(r), \(b.n) beats)"
    }

    var lockColor: Color {
        let x = rec.live.beat.lock
        guard x.isFinite else { return Color.secondary }
        if rec.mode == .table { return x > 3 ? Color.orange : Color.green }
        return x > 6 ? Color.green : (x > 3 ? Color.orange : Color.red)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(title).font(.headline).multilineTextAlignment(.center).padding(.horizontal)
                Text("\(rec.remaining)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                FingerLightView(r: Double(rec.live.r), sat: Double(rec.live.sat))
                    .padding(.horizontal)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Finger pulse (\(rec.live.beat.channel.uppercased()), filtered)").font(.caption)
                        Spacer()
                        Text(hrText).font(.caption.bold())
                    }
                    Wave(values: rec.live.ppg).stroke(Color.red, lineWidth: 1.5).frame(height: 70)
                    Text("Chest accelerometer (−z, 5–40 Hz)").font(.caption)
                    Wave(values: rec.live.scg).stroke(Color.blue, lineWidth: 1).frame(height: 70)
                    Text("Chest beat average, aligned to the finger pulse (last 20 s)").font(.caption)
                    TracePlot(values: rec.live.beat.avg, start: rec.live.beat.startMs, dx: rec.live.beat.dtMs,
                              xMin: -500, xMax: 100, color: .blue, lines: [VLine(x: 0, color: .orange)], height: 70)
                    Text(lockText).font(.caption.bold()).foregroundColor(lockColor)
                    Text("Orange line = finger pulse. A repeating bump to its left is the heartbeat reaching the phone. If it stays \"not yet\", shift the phone 1 to 2 cm along the breastbone.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(.horizontal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lens: \(rec.lens.title)   Flash: \(rec.torchNowPct)%" + (rec.torchNowPct > rec.torchStartPct ? " (raised)" : ""))
                    Text("Finger colour: \(rec.colourChannel == nil ? "automatic" : ColourProfile.name(rec.colourChannel))")
                    Text(String(format: "Camera %.0f fps   Accelerometer %.0f Hz", rec.live.fps, rec.live.accHz))
                    Text(String(format: "R %.0f  G %.0f  B %.0f   saturated %.1f%%", rec.live.r, rec.live.g, rec.live.b, rec.live.sat))
                    Text(String(format: "ISO %.0f   exposure %.2f ms", rec.live.iso, rec.live.expMs))
                }
                .font(.system(.footnote, design: .monospaced))
                HStack(spacing: 16) {
                    HoldButton(title: "Hold to Mark", color: .blue) { t in rec.mark(at: t) }
                    HoldButton(title: "Hold to Stop", color: .red) { _ in rec.stopEarly() }
                }
                .disabled(rec.phase == .saving)
                Text("Buttons need a 1.5 s hold. The screen switches off while it touches your chest and wakes when you lift the phone. You'll hear the result when it ends.")
                    .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            }
            .padding(.vertical)
        }
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }
}

/// Rear lenses: only the ones this iPhone has can be chosen; the rest are greyed out.
struct LensChooser: View {
    @ObservedObject var rec: Recorder

    var body: some View {
        if CameraLens.available.count <= 1 {
            HStack {
                Text("Lens")
                Spacer()
                Text("\(rec.lens.title), the only rear camera").foregroundColor(.secondary)
            }
        } else {
            ForEach(CameraLens.allCases) { l in
                Button {
                    rec.lens = l
                } label: {
                    HStack {
                        Text(l.title)
                            .foregroundColor(l.isAvailable ? Color.primary : Color.secondary)
                        Spacer()
                        Text(lensNote(l)).font(.caption).foregroundColor(.secondary)
                        if rec.lens == l {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .disabled(!l.isAvailable)
            }
            Text("Choose the lens your fingertip can cover together with the flash (the phone can't tell which one is nearest). Your choice is remembered for every recording on this phone.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    func lensNote(_ l: CameraLens) -> String {
        if !l.isAvailable { return "not on this phone" }
        let f = CameraLens.maxFPS[l] ?? 0
        if f > 0 && f < 119 { return String(format: "max %.0f fps", f) }
        return ""
    }
}

/// Red level of the fingertip image, with the target zone the exposure controller aims for (150-235).
struct FingerLightView: View {
    let r: Double
    let sat: Double      // percent of pixels saturated

    var status: (String, Color) {
        if r <= 0 { return ("Waiting for camera…", Color.secondary) }
        if r < 60 {
            return ("Too dark: the flash light isn't reaching the camera. Cover the lens and the flash with one fingertip, or pick another lens.", Color.red)
        }
        if sat > 2 || r > 245 { return ("Too bright: press a little lighter or shift your finger.", Color.orange) }
        if r < 150 { return ("Dim: usable if the pulse line is smooth.", Color.orange) }
        return ("Good finger light.", Color.green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Finger light (red level, green zone = target)").font(.caption)
                Spacer()
                Text(String(format: "%.0f / 255", r)).font(.caption.bold())
            }
            LevelBar(value: r)
            Text(status.0).font(.caption).foregroundColor(status.1)
        }
    }
}

struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25))
                Rectangle().fill(Color.green.opacity(0.35))
                    .frame(width: g.size.width * 85 / 255)
                    .offset(x: g.size.width * 150 / 255)
                RoundedRectangle(cornerRadius: 4).fill(Color.red)
                    .frame(width: max(2, g.size.width * CGFloat(min(max(value, 0), 255) / 255)))
            }
        }
        .frame(height: 14)
    }
}

/// Button that only fires after a 1.5 s hold, so skin contact can't trigger it.
/// The action receives the time the press started. No haptic: vibration would shake the accelerometer.
struct HoldButton: View {
    let title: String
    let color: Color
    let action: (Double) -> Void
    @State private var pressing = false
    @State private var pressStart = 0.0

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(color.opacity(pressing ? 0.55 : 0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
            .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 40, perform: {
                action(pressStart)
            }, onPressingChanged: { p in
                pressing = p
                if p { pressStart = HostClock.now }
            })
    }
}

struct ResultView: View {
    @ObservedObject var rec: Recorder

    var body: some View {
        Form {
            Section("Signal check") {
                ForEach(rec.summary) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.value).foregroundColor(.secondary)
                        if let ok = row.ok {
                            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(ok ? .green : .orange)
                        }
                    }
                    .font(.callout)
                }
            }
            Section("Analysis (on the phone)") {
                if rec.analyzing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Analysing…").foregroundColor(.secondary)
                    }
                } else if let e = rec.analysisError {
                    Text(e).foregroundColor(.red).font(.callout)
                } else if let a = rec.analysis {
                    VerdictRows(r: a)
                    NavigationLink(destination: AnalysisDetailView(r: a)) {
                        Text("Charts and full analysis")
                    }
                }
            }
            if let e = rec.errorMessage {
                Section { Text(e).foregroundColor(.red) }
            }
            Section("Cuff reading for this session (optional)") {
                TextField("Systolic (mmHg)", text: $rec.cuffSBP).keyboardType(.numberPad)
                TextField("Diastolic (mmHg)", text: $rec.cuffDBP).keyboardType(.numberPad)
                TextField("Notes (posture, activity, finger)", text: $rec.notes)
                Button("Save to this recording") { rec.saveCuff() }
                if !rec.savedNote.isEmpty { Text(rec.savedNote).font(.caption) }
            }
            Section {
                if let f = rec.currentFolder {
                    Button("Share this recording") { rec.share(f) }
                }
                Button("New recording") { rec.newRecording() }
            }
        }
    }
}

struct Wave: Shape {
    var values: [Double]

    func path(in r: CGRect) -> Path {
        var p = Path()
        let finite = values.filter { $0.isFinite }
        guard values.count > 1, let mn = finite.min(), let mx = finite.max(), mx > mn else { return p }
        for (i, v0) in values.enumerated() {
            let v = v0.isFinite ? v0 : mn
            let x = r.minX + r.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = r.maxY - r.height * CGFloat((v - mn) / (mx - mn))
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
