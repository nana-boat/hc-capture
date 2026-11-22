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
                Text("Research prototype. Not a medical device. This app records signals only and shows no blood pressure.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("Recording type") {
                Picker("Mode", selection: $rec.mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(rec.mode.instructions).font(.callout)
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
                    Button { rec.share(url) } label: {
                        Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                }
                .onDelete { rec.delete(at: $0) }
                if !rec.recordings.isEmpty {
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
        case .preparing: return "Get in position. Camera is adjusting."
        case .recording: return "Recording. Stay still."
        default: return "Saving…"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text("\(rec.remaining)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 4) {
                Text("Finger pulse (green, inverted)").font(.caption)
                Wave(values: rec.live.ppg).stroke(Color.red, lineWidth: 1.5).frame(height: 70)
                Text("Chest accelerometer (−z)").font(.caption)
                Wave(values: rec.live.scg).stroke(Color.blue, lineWidth: 1).frame(height: 70)
            }
            .padding(.horizontal)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Camera %.0f fps   Accelerometer %.0f Hz", rec.live.fps, rec.live.accHz))
                Text(String(format: "R %.0f  G %.0f  B %.0f   saturated %.1f%%", rec.live.r, rec.live.g, rec.live.b, rec.live.sat))
                Text(String(format: "ISO %.0f   exposure %.2f ms", rec.live.iso, rec.live.expMs))
            }
            .font(.system(.footnote, design: .monospaced))
            HStack(spacing: 20) {
                Button("Mark") { rec.mark() }.buttonStyle(.bordered)
                Button("Stop", role: .destructive) { rec.stopEarly() }.buttonStyle(.borderedProminent)
            }
            .disabled(rec.phase == .saving)
            Spacer()
        }
        .padding(.top)
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
                Text("Heartbeat timing, PTT and PIR are worked out on your laptop with hc_analyze.py.")
                    .font(.caption).foregroundColor(.secondary)
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
        guard values.count > 1, let mn = values.min(), let mx = values.max(), mx > mn else { return p }
        for (i, v) in values.enumerated() {
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
