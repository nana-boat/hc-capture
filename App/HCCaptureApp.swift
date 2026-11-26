import SwiftUI
import UIKit

@main
struct HCCaptureApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// App version from Info.plist, written into every saved file.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}

// MARK: - look (0.4.2: minimal, one accent colour; a full design comes later)

enum Theme {
    static let accent = Color(red: 15 / 255, green: 118 / 255, blue: 110 / 255)   // teal #0F766E
    static let warn = Color(red: 180 / 255, green: 83 / 255, blue: 9 / 255)       // amber #B45309
    static let bg = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardModifier(padding: padding)) }
}

struct MainButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(filled ? Theme.accent : Theme.card)
            .foregroundColor(filled ? .white : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

enum ChipKind { case good, weak, neutral }

func chipColor(_ k: ChipKind) -> Color {
    switch k {
    case .good: return Theme.accent
    case .weak: return Theme.warn
    case .neutral: return Color.secondary
    }
}

struct Chip: View {
    let text: String
    let kind: ChipKind

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(chipColor(kind))
            .background(chipColor(kind).opacity(0.12))
            .clipShape(Capsule())
    }
}

/// One line in a card: label on the left, value on the right.
struct CardRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            value()
        }
        .font(.callout)
        .padding(.vertical, 8)
    }
}

struct NumberTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .card(padding: 10)
    }
}

// MARK: - app

struct ContentView: View {
    @StateObject private var rec = Recorder()

    var body: some View {
        NavigationStack {
            Group {
                switch rec.phase {
                case .idle: HomeView(rec: rec)
                case .preparing: GetReadyView(rec: rec)
                case .recording, .saving: RecordingView(rec: rec)
                case .done: ResultView(rec: rec)
                }
            }
        }
        .tint(Theme.accent)
        .sheet(item: $rec.shareItem) { item in ActivityView(items: [item.url]) }
    }
}

// MARK: - 1. home

/// A saved recording for the home list. Folder names are yyyyMMdd_HHmmss_mode.
struct RecordingItem: Identifiable {
    let url: URL
    let result: AnalysisResult?
    var id: URL { url }
    var parts: [String] { url.lastPathComponent.split(separator: "_").map(String.init) }
    var kind: String { parts.last ?? "" }
    var time: String {
        guard parts.count >= 2 else { return url.lastPathComponent }
        let t = Array(parts[1])
        guard t.count >= 4 else { return parts[1] }
        return "\(t[0])\(t[1]):\(t[2])\(t[3])"
    }
    var title: String {
        var s = "\(time) · \(kind.capitalized)"
        if kind == "chest", let p = result?.placement, p != BodyPlacement.sternum.rawValue {
            s += " · " + (BodyPlacement(rawValue: p)?.short ?? p)
        }
        return s
    }
    var chip: (String, ChipKind) {
        guard let r = result else { return ("Not analysed", .neutral) }
        if kind == "chest" {
            guard let g = r.grade else { return ("No grade", .neutral) }
            return g.good ? ("Good · \(fmt(g.pttMedianMs, "%.0f")) ms", .good) : ("Weak", .weak)
        }
        if kind == "table" && r.bestLock.isFinite && r.bestLock > 3 { return ("Pulse leak", .weak) }
        return ("Done", .neutral)
    }
}

struct HomeView: View {
    @ObservedObject var rec: Recorder
    @State private var showSettings = false
    @State private var today: [RecordingItem] = []

    var siteOptions: [BodyPlacement] { rec.placementTest ? BodyPlacement.testSites : BodyPlacement.allCases }

    /// With the site test on, the picker chooses the test site; otherwise the site of the next recording.
    var site: Binding<BodyPlacement> {
        Binding(get: { rec.placementTest ? rec.testSite : rec.placement },
                set: { v in
                    if rec.placementTest { rec.testSite = v } else { rec.placement = v }
                })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Research prototype. Not a medical device. Shows no blood pressure.")
                    .font(.footnote).foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Picker("Mode", selection: $rec.mode) {
                        ForEach(Mode.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 6)
                    if rec.mode == .chest {
                        CardRow(label: rec.placementTest ? "Test site" : "Site") {
                            Picker("Site", selection: site) {
                                ForEach(siteOptions) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        Divider()
                        CardRow(label: "Phone") {
                            Text(rec.placement.turnTitle).foregroundColor(.secondary)
                        }
                        if rec.placementTest {
                            Divider()
                            CardRow(label: "Next recording") {
                                Text(rec.placement.title).foregroundColor(Theme.accent)
                            }
                        }
                    } else {
                        Text(rec.mode.instructions)
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.top, 6)
                    }
                }
                .card()

                if let e = rec.errorMessage {
                    Text(e).font(.callout).foregroundColor(.red)
                }
                Button {
                    Task { await rec.start() }
                } label: {
                    Text("Start")
                }
                .buttonStyle(MainButtonStyle())

                Text("Today").font(.footnote).foregroundColor(.secondary).padding(.leading, 4)
                VStack(spacing: 0) {
                    if today.isEmpty {
                        Text("No recordings today").font(.callout).foregroundColor(.secondary).padding(.vertical, 8)
                    }
                    ForEach(Array(today.enumerated()), id: \.element.id) { i, it in
                        if i > 0 { Divider() }
                        NavigationLink(destination: SessionDetailView(rec: rec, folder: it.url)) {
                            HStack(spacing: 8) {
                                Text(it.title).foregroundColor(.primary).lineLimit(1)
                                Spacer(minLength: 4)
                                Chip(text: it.chip.0, kind: it.chip.1)
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                            }
                            .font(.callout)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .card(padding: 12)

                HStack {
                    NavigationLink(destination: CompareView(rec: rec)) { Text("Compare") }
                    Spacer()
                    NavigationLink(destination: AllRecordingsView(rec: rec)) { Text("All recordings") }
                    Spacer()
                    Button("Share all") { rec.shareAll() }
                }
                .font(.callout)
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("HC Capture")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(rec: rec) }
        .onAppear { reload() }
        .onChange(of: rec.recordings) { _ in reload() }
    }

    /// Today's recordings, newest first (at most 10; the rest are under All recordings).
    private func reload() {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        let d = f.string(from: Date())
        today = rec.recordings.filter { $0.lastPathComponent.hasPrefix(d) }.prefix(10)
            .map { RecordingItem(url: $0, result: Analyzer.loadSaved($0)) }
    }
}

struct AllRecordingsView: View {
    @ObservedObject var rec: Recorder

    var body: some View {
        List {
            Section {
                if rec.recordings.isEmpty {
                    Text("None yet").foregroundColor(.secondary)
                }
                ForEach(rec.recordings, id: \.self) { url in
                    NavigationLink(destination: SessionDetailView(rec: rec, folder: url)) {
                        Label(url.lastPathComponent, systemImage: "waveform.path.ecg")
                    }
                }
                .onDelete { rec.delete(at: $0) }
            } footer: {
                Text("Also in Files > On My iPhone > HC Capture.")
            }
        }
        .navigationTitle("All recordings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 2. get ready (positioning)

struct GetReadyView: View {
    @ObservedObject var rec: Recorder

    var items: [ChecklistItem] { ChecklistItem.items(for: rec.mode) }

    var siteTitle: String {
        switch rec.mode {
        case .chest: return "\(rec.placement.title) · \(rec.placement.turnName)"
        case .table: return "Table control"
        case .tap: return "Tap sync test"
        }
    }

    var siteText: String { rec.mode == .chest ? rec.placement.instructions : rec.mode.instructions }

    var pillText: String {
        if !rec.prepStatus.isEmpty { return rec.prepStatus }
        return rec.usesDoubleTap ? "Positioning…" : "Recording starts in \(rec.remaining) s"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Divider() }
                        Button {
                            rec.toggleCheck(item.key)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: rec.checklist[item.key] == true ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(rec.checklist[item.key] == true ? Theme.accent : Color.secondary)
                                Text(item.text).foregroundColor(.primary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .font(.callout)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .card(padding: 12)

                FingerLightView(r: Double(rec.live.r), sat: Double(rec.live.sat)).card()

                VStack(alignment: .leading, spacing: 4) {
                    Text(siteTitle).font(.callout.weight(.semibold))
                    Text(siteText).font(.caption).foregroundColor(.secondary)
                }
                .card()

                Text(pillText)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                if rec.mode != .tap { HeartbeatLine(rec: rec).padding(.horizontal, 4) }
                if rec.usesDoubleTap {
                    Text("Stops by itself in \(rec.remaining) s if there is no double tap.")
                        .font(.caption2).foregroundColor(.secondary).padding(.horizontal, 4)
                }

                SignalDetails(rec: rec).card()
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Get ready")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { rec.stopEarly() }
            }
        }
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }
}

/// Heartbeat status line (chest) or pulse-leak status (table), with the live heart rate.
struct HeartbeatLine: View {
    @ObservedObject var rec: Recorder

    var state: (String, ChipKind) {
        let b = rec.live.beat
        guard b.lock.isFinite else {
            return (rec.mode == .table ? "Collecting beats…" : "Looking for the heartbeat…", .neutral)
        }
        if rec.mode == .table { return b.lock > 3 ? ("Finger pulse leaking into motion", .weak) : ("No pulse leak", .good) }
        if b.lock > 6 { return ("Heartbeat found", .good) }
        return b.lock > 3 ? ("Heartbeat weak", .weak) : ("No heartbeat yet", .weak)
    }

    var hr: String { rec.live.beat.hr.isFinite ? String(format: "%.0f bpm", rec.live.beat.hr) : "– bpm" }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(chipColor(state.1)).frame(width: 8, height: 8)
            Text(state.0).font(.callout.weight(.semibold)).foregroundColor(chipColor(state.1))
            Spacer()
            Text(hr).font(.callout).foregroundColor(.secondary).monospacedDigit()
        }
    }
}

/// Live signals and camera numbers, folded away by default.
struct SignalDetails: View {
    @ObservedObject var rec: Recorder
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Finger pulse (\(rec.live.beat.channel.uppercased()), filtered)").font(.caption)
                Wave(values: rec.live.ppg).stroke(Color.primary, lineWidth: 1.2).frame(height: 56)
                Text("Chest, out of the chest, 5–40 Hz").font(.caption)
                Wave(values: rec.live.scg).stroke(Color.primary, lineWidth: 1).frame(height: 56)
                Text("Chest beat average, aligned to the finger pulse (last 20 s)").font(.caption)
                TracePlot(values: rec.live.beat.avg, start: rec.live.beat.startMs, dx: rec.live.beat.dtMs,
                          xMin: -500, xMax: 100, color: Theme.accent, lines: [VLine(x: 0, color: Color.secondary)],
                          height: 64)
                Group {
                    Text("Lens \(rec.lens.title) · flash \(rec.torchNowPct)%" + (rec.torchNowPct > rec.torchStartPct ? " (raised)" : ""))
                    Text("Finger colour: \(rec.colourChannel == nil ? "automatic" : ColourProfile.name(rec.colourChannel))")
                    Text(String(format: "Camera %.0f fps · accelerometer %.0f Hz", rec.live.fps, rec.live.accHz))
                    Text(String(format: "R %.0f  G %.0f  B %.0f · saturated %.1f%%", rec.live.r, rec.live.g, rec.live.b, rec.live.sat))
                    Text(String(format: "ISO %.0f · exposure %.2f ms", rec.live.iso, rec.live.expMs))
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
            }
            .padding(.top, 6)
        } label: {
            Text("Signal details").font(.callout).foregroundColor(.primary)
        }
    }
}

// MARK: - 3. recording

struct RecordingView: View {
    @ObservedObject var rec: Recorder

    func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    var progress: Double { rec.targetS > 0 ? min(1, Double(rec.elapsedS) / Double(rec.targetS)) : 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if rec.phase == .saving {
                    ProgressView("Saving…").padding(.top, 40)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(clock(rec.elapsedS)).font(.system(size: 56, weight: .light)).monospacedDigit()
                        Text("/ " + clock(rec.targetS)).font(.title3).foregroundColor(.secondary).monospacedDigit()
                    }
                    .padding(.top, 8)
                    ProgressView(value: progress).tint(Theme.accent)
                    HeartbeatLine(rec: rec)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finger pulse").font(.caption).foregroundColor(.secondary)
                        Wave(values: rec.live.ppg).stroke(Color.primary, lineWidth: 1.5).frame(height: 56)
                    }
                    .card()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chest").font(.caption).foregroundColor(.secondary)
                        Wave(values: rec.live.scg).stroke(Color.primary, lineWidth: 1).frame(height: 56)
                    }
                    .card()
                    Text("Keep still. Breathe normally. No talking.\nThe screen turns off on your chest.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        HoldButton(title: "Hold to mark", color: Theme.accent) { t in rec.mark(at: t) }
                        HoldButton(title: "Hold to stop", color: Theme.warn) { _ in rec.stopEarly() }
                    }
                    Text("Buttons need a 1.5 s hold. You'll hear the result when it ends.")
                        .font(.caption2).foregroundColor(.secondary).multilineTextAlignment(.center)
                    SignalDetails(rec: rec).card()
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(rec.phase == .saving ? "Saving" : "Recording")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }
}

// MARK: - 4. result

struct ResultView: View {
    @ObservedObject var rec: Recorder
    @State private var showCuff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if rec.analyzing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Analysing…").foregroundColor(.secondary)
                    }
                    .card()
                } else if let e = rec.analysisError {
                    Text(e).font(.callout).foregroundColor(.red).card()
                } else if let a = rec.analysis {
                    ResultSummary(rec: rec, r: a)
                }
                if let e = rec.errorMessage {
                    Text(e).font(.callout).foregroundColor(.red)
                }
                SignalCheck(rows: rec.summary).card()

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        showCuff.toggle()
                    } label: {
                        HStack {
                            Text("Cuff reading (optional)").foregroundColor(.primary)
                            Spacer()
                            Text(showCuff ? "Close" : "Add").foregroundColor(Theme.accent)
                        }
                        .font(.callout)
                    }
                    if showCuff {
                        TextField("Systolic (mmHg)", text: $rec.cuffSBP).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        TextField("Diastolic (mmHg)", text: $rec.cuffDBP).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        TextField("Notes (posture, activity, finger)", text: $rec.notes).textFieldStyle(.roundedBorder)
                        Button("Save to this recording") { rec.saveCuff() }.font(.callout.weight(.semibold))
                        if !rec.savedNote.isEmpty {
                            Text(rec.savedNote).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .card()

                HStack(spacing: 10) {
                    Button("New recording") { rec.newRecording() }.buttonStyle(MainButtonStyle())
                    if let f = rec.currentFolder {
                        Button("Share") { rec.share(f) }.buttonStyle(MainButtonStyle(filled: false))
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { rec.newRecording() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let a = rec.analysis {
                    NavigationLink(destination: AnalysisDetailView(r: a)) { Text("Details") }
                }
            }
        }
    }
}

struct ResultSummary: View {
    @ObservedObject var rec: Recorder
    let r: AnalysisResult

    /// Verdict text, icon and colour.
    var verdict: (String, String, Color) {
        if let t = r.tap {
            let ok = t.accTaps >= 4 && t.paired >= 4
            return (ok ? "Tap test done" : "Too few taps", ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    ok ? Theme.accent : Theme.warn)
        }
        if r.mode == "table" {
            let leak = r.bestLock.isFinite && r.bestLock > 3
            return (leak ? "Pulse leak" : "No pulse leak", leak ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    leak ? Theme.warn : Theme.accent)
        }
        guard let g = r.grade else { return ("No grade", "questionmark.circle", Color.secondary) }
        return g.good ? ("Good", "checkmark.circle.fill", Theme.accent) : ("Weak", "exclamationmark.triangle.fill", Theme.warn)
    }

    var line: String {
        var parts = [r.mode.capitalized]
        if r.mode == "chest" { parts.append(Analyzer.placementName(r.placement)) }
        if !rec.lastTime.isEmpty { parts.append(rec.lastTime) }
        if rec.lastLengthS > 0 { parts.append("\(rec.lastLengthS) s") }
        return parts.joined(separator: " · ")
    }

    func templateLines(_ p: PlotData) -> [VLine] {
        var l = [VLine(x: 0, color: Color.secondary)]
        if let a = p.aoMs { l.append(VLine(x: a, color: Theme.accent)) }
        return l
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: verdict.1).foregroundColor(verdict.2)
                Text(verdict.0)
            }
            .font(.system(size: 28, weight: .bold))
            Text(line).font(.footnote).foregroundColor(.secondary)

            if r.mode == "chest" {
                HStack(spacing: 8) {
                    NumberTile(value: fmt(r.grade?.pttMedianMs ?? .nan, "%.0f"), label: "PTT, ms")
                    NumberTile(value: fmt(r.hrPpg, "%.0f"), label: "Heart rate")
                    NumberTile(value: fmt(r.grade?.pttSpreadMs ?? .nan, "%.1f"), label: "Spread, ms")
                }
                if let g = r.grade, !g.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(g.reasons, id: \.self) { Text("• " + $0) }
                    }
                    .font(.caption)
                    .foregroundColor(Theme.warn)
                    .card()
                }
                if let p = r.plot, !p.tmpl.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Averaged heartbeat").font(.caption).foregroundColor(.secondary)
                        TracePlot(values: p.tmpl, start: p.tmplStartMs, dx: p.tmplDtMs, xMin: p.tmplStartMs,
                                  xMax: p.tmplStartMs + p.tmplDtMs * Double(p.tmpl.count), color: .primary,
                                  lines: templateLines(p), height: 110)
                        HStack {
                            Text("valve opening").foregroundColor(Theme.accent)
                            Spacer()
                            Text("finger pulse").foregroundColor(.secondary)
                        }
                        .font(.caption2)
                    }
                    .card()
                }
            } else if let t = r.tap {
                VStack(spacing: 0) {
                    CardRow(label: "Taps felt / seen by camera") { Text("\(t.accTaps) / \(t.paired)").foregroundColor(.secondary) }
                    Divider()
                    CardRow(label: "Camera minus motion") { Text("\(fmt(t.offsetMedianMs)) ms").foregroundColor(.secondary) }
                    Divider()
                    CardRow(label: "Spread (SD)") { Text("\(fmt(t.offsetSdMs)) ms").foregroundColor(.secondary) }
                }
                .card(padding: 12)
                Text("Do 3 repeats. A steady offset between repeats matters more than a zero offset.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    NumberTile(value: fmt(r.hrPpg, "%.0f"), label: "Heart rate")
                    NumberTile(value: fmt(r.bestLock), label: "Pulse in motion data")
                }
                Text("The table control should show no heartbeat in the motion data (ratio below 3, about 1).")
                    .font(.caption).foregroundColor(.secondary)
            }

            if r.isFlagged {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(r.flags ?? [], id: \.self) { f in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "flag.fill")
                            Text(f)
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(Theme.warn)
                .card()
            }
        }
    }
}

/// The capture check (rates, dropped frames, light), folded away by default.
struct SignalCheck: View {
    let rows: [SummaryRow]
    @State private var open = false

    var allOK: Bool { rows.allSatisfy { $0.ok != false } }

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.value).foregroundColor(.secondary)
                        if let ok = row.ok {
                            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(ok ? Theme.accent : Theme.warn)
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("Capture check").font(.callout).foregroundColor(.primary)
                Spacer()
                Chip(text: allOK ? "OK" : "Check", kind: allOK ? .good : .weak)
            }
        }
    }
}

// MARK: - settings

struct SettingsView: View {
    @ObservedObject var rec: Recorder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Alternate with lower breastbone", isOn: $rec.placementTest)
                    if rec.placementTest {
                        Picker("Test site", selection: $rec.testSite) {
                            ForEach(BodyPlacement.testSites) { Text($0.title).tag($0) }
                        }
                    }
                } header: {
                    Text("Site test")
                } footer: {
                    Text(rec.placementTest
                         ? "Each chest recording switches: test site, lower breastbone, test site, and so on. Next: \(rec.placement.title)."
                         : "For the site test: the app switches between a test site and the lower breastbone after each chest recording.")
                }

                Section {
                    Picker("Start recording by", selection: $rec.startMethod) {
                        ForEach(StartMethod.allCases) { Text($0.title).tag($0) }
                    }
                    if !(rec.mode == .chest && rec.startMethod == .doubleTap) {
                        Picker("Positioning time", selection: $rec.settle) {
                            ForEach([7, 10, 15], id: \.self) { Text("\($0) s").tag($0) }
                        }
                    }
                    Picker("Recording length", selection: $rec.duration) {
                        Text("45 s, up to 60 s if needed").tag(45)
                        Text("60 s").tag(60)
                        Text("90 s").tag(90)
                    }
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Double tap: tap any part of the phone firmly with your other hand once the app says the phone is in place. If iPhone Back Tap is on, tap the edge or turn Back Tap off. With 45 s, chest recordings carry on to 60 s by themselves if they are not Good yet.")
                }

                Section {
                    LensChooser(rec: rec)
                    Picker("Camera frame rate", selection: $rec.fps) {
                        ForEach([60, 120, 240], id: \.self) { Text("\($0) fps").tag($0) }
                    }
                    HStack {
                        Text("Flash")
                        Spacer()
                        Text("starts at \(rec.torchStartPct)%, automatic").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Finger colour")
                        Spacer()
                        Text(rec.colourChannel == nil ? "not chosen yet" : ColourProfile.name(rec.colourChannel))
                            .foregroundColor(.secondary)
                    }
                    if rec.colourChannel != nil {
                        Button("Choose finger colour again (new person)") { rec.resetColour() }
                    }
                    if !rec.colourMessage.isEmpty {
                        Text(rec.colourMessage).font(.caption).foregroundColor(Theme.warn)
                    }
                } header: {
                    Text("Camera")
                } footer: {
                    Text("The flash is raised only while positioning, if the finger is too dim, and never changes during a recording. The finger colour is chosen on the first clean recording and then kept.")
                }

                Section {
                    Picker("Accelerometer request", selection: $rec.accHz) {
                        ForEach([100, 200, 400], id: \.self) { Text("\($0) Hz").tag($0) }
                    }
                    NavigationLink(destination: FastSensorTestView()) {
                        Label("Fast motion-data test (about 2 min)", systemImage: "speedometer")
                    }
                } header: {
                    Text("Motion")
                } footer: {
                    Text("iPhones often cap the accelerometer near 100 Hz; the real rate is measured and saved. The test checks whether this phone gives faster motion data. Phone flat on a table.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(AppInfo.version).foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Research prototype. Not a medical device. This app records and analyses signals only and shows no blood pressure.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }
}

// MARK: - shared pieces (kept from 0.4.1, restyled)

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
                            Image(systemName: "checkmark").foregroundColor(Theme.accent)
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

    var status: (String, String, ChipKind) {
        if r <= 0 { return ("Waiting for camera…", "–", .neutral) }
        if r < 60 {
            return ("The flash light isn't reaching the camera. Cover the lens and the flash with one fingertip, or pick another lens.", "Too dark", .weak)
        }
        if sat > 2 || r > 245 { return ("Press a little lighter or shift your finger.", "Too bright", .weak) }
        if r < 150 { return ("Usable if the pulse line is smooth.", "Dim", .weak) }
        return ("Keep the marker in the green zone. Light, steady press; don't press hard.", "Good", .good)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Finger light").font(.callout)
                Spacer()
                Chip(text: status.1, kind: status.2)
            }
            LevelBar(value: r)
            Text(status.0).font(.caption).foregroundColor(.secondary)
        }
    }
}

struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 8)
                Capsule().fill(Theme.accent.opacity(0.25))
                    .frame(width: g.size.width * 85 / 255, height: 8)
                    .offset(x: g.size.width * 150 / 255)
                Capsule().fill(Theme.accent)
                    .frame(width: 4, height: 18)
                    .offset(x: max(0, min(g.size.width - 4, g.size.width * CGFloat(min(max(value, 0), 255) / 255) - 2)))
            }
            .frame(height: 18)
        }
        .frame(height: 18)
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundColor(color)
            .background(pressing ? color.opacity(0.18) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1.5))
            .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 40, perform: {
                action(pressStart)
            }, onPressingChanged: { p in
                pressing = p
                if p { pressStart = HostClock.now }
            })
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
