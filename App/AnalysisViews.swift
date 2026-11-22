import SwiftUI
import UIKit

func fmt(_ v: Double, _ f: String = "%.1f") -> String { v.isFinite ? String(format: f, v) : "–" }

// MARK: - small building blocks

struct ResultLine: View {
    let label: String
    let value: String
    let ok: Bool?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
            if let ok = ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(ok ? .green : .orange)
            }
        }
        .font(.callout)
    }
}

struct VLine {
    var x: Double
    var color: Color
}

/// Line plot drawn with Canvas. values[i] sits at x = start + i * dx.
struct TracePlot: View {
    var values: [Double]
    var start: Double
    var dx: Double
    var xMin: Double
    var xMax: Double
    var color: Color = .primary
    var lines: [VLine] = []
    var lower: [Double]? = nil
    var upper: [Double]? = nil
    var height: CGFloat = 90

    var body: some View {
        Canvas { ctx, size in
            var all = values.filter { $0.isFinite }
            if let l = lower { all += l.filter { $0.isFinite } }
            if let u = upper { all += u.filter { $0.isFinite } }
            guard let lo = all.min(), let hi = all.max(), hi > lo, xMax > xMin else { return }
            let w = Double(size.width), h = Double(size.height)
            func px(_ x: Double) -> CGFloat { CGFloat((x - xMin) / (xMax - xMin) * w) }
            func py(_ y: Double) -> CGFloat { CGFloat(h - 4 - (y - lo) / (hi - lo) * (h - 8)) }
            if let l = lower, let u = upper, l.count == u.count, l.count > 1 {
                var band = Path()
                var first = true
                for i in 0..<u.count where u[i].isFinite {
                    let pt = CGPoint(x: px(start + Double(i) * dx), y: py(u[i]))
                    if first { band.move(to: pt); first = false } else { band.addLine(to: pt) }
                }
                for i in stride(from: l.count - 1, through: 0, by: -1) where l[i].isFinite {
                    band.addLine(to: CGPoint(x: px(start + Double(i) * dx), y: py(l[i])))
                }
                band.closeSubpath()
                ctx.fill(band, with: .color(color.opacity(0.18)))
            }
            for v in lines where v.x >= xMin && v.x <= xMax {
                var p = Path()
                let x = px(v.x)
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: CGFloat(h)))
                ctx.stroke(p, with: .color(v.color.opacity(0.75)), lineWidth: 1)
            }
            var path = Path()
            var started = false
            for (i, v) in values.enumerated() {
                if !v.isFinite { started = false; continue }
                let pt = CGPoint(x: px(start + Double(i) * dx), y: py(v))
                if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.2)
        }
        .frame(height: height)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ScatterPlot: View {
    var points: [SeriesPoint]
    var color: Color
    var height: CGFloat = 90

    var body: some View {
        Canvas { ctx, size in
            let pts = points.filter { $0.x.isFinite && $0.y.isFinite }
            let xs = pts.map { $0.x }, ys = pts.map { $0.y }
            guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return }
            let dx = max(x1 - x0, 1e-9), dy = max(y1 - y0, 1e-9)
            let w = Double(size.width), h = Double(size.height)
            for p in pts {
                let cx = (p.x - x0) / dx * (w - 8) + 4
                let cy = h - 4 - (p.y - y0) / dy * (h - 8)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4)), with: .color(color))
            }
        }
        .frame(height: height)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - headline results

struct VerdictRows: View {
    let r: AnalysisResult

    var body: some View {
        Group {
            if let tap = r.tap {
                ResultLine(label: "Taps felt / seen by camera", value: "\(tap.accTaps) / \(tap.paired)", ok: tap.accTaps >= 4 && tap.paired >= 4)
                ResultLine(label: "Camera minus accel offset", value: "\(fmt(tap.offsetMedianMs)) ms", ok: nil)
                ResultLine(label: "Offset spread (SD)", value: "\(fmt(tap.offsetSdMs)) ms", ok: nil)
                Text("Do 3 repeats. A steady offset between repeats matters more than a zero offset.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                if let g = r.grade {
                    ResultLine(label: "Recording grade", value: g.good ? "Good" : "Weak", ok: g.good)
                    ForEach(g.reasons, id: \.self) { reason in
                        Text("• " + reason).font(.caption).foregroundColor(.orange)
                    }
                    ResultLine(label: "Placement", value: Analyzer.placementName(r.placement)
                               + ((r.extended ?? false) ? " · extended to 60 s" : ""), ok: nil)
                }
                ResultLine(label: "Heart rate (finger / chest)", value: hrText, ok: nil)
                ResultLine(label: "Finger beats passing quality", value: "\(r.nPpgOk) / \(r.nBeats)",
                           ok: r.nPpgOk >= Analyzer.minValidBeats)
                if r.mode == "table" {
                    ResultLine(label: "Leak where the chest test looks", value: lockText,
                               ok: r.bestLock.isFinite ? r.bestLock <= 3 : nil)
                    if r.anyLock.isFinite && r.locks.contains(where: { $0.axis != nil }) {
                        ResultLine(label: "Any finger movement (all directions)", value: "ratio \(fmt(r.anyLock))", ok: nil)
                    }
                } else if !r.locks.isEmpty {
                    ResultLine(label: "Heartbeat in chest signal", value: lockText, ok: r.bestLock > 6)
                }
                if r.mode != "table", let fx = r.fixed {
                    ResultLine(label: "PTT (fixed method)", value: pttText(fx),
                               ok: (r.scgDetected ?? false) && fx.valid >= Analyzer.minValidBeats)
                }
                if r.pirMedian.isFinite {
                    ResultLine(label: "PIR (median, CV)", value: "\(fmt(r.pirMedian, "%.3f")), \(fmt(r.pirCv))%", ok: nil)
                }
            }
            ForEach(r.flags ?? [], id: \.self) { f in
                Label(f, systemImage: "flag.fill").font(.caption).foregroundColor(.orange)
            }
            ForEach(r.notes ?? [], id: \.self) { nt in
                Text(nt).font(.caption).foregroundColor(.secondary)
            }
            ForEach(r.warnings, id: \.self) { w in
                Text(w).font(.caption).foregroundColor(.red)
            }
            if r.version < 3 && r.tap == nil {
                Text("Analysed with an older app version. Re-analyse to use version 2 (corrected chest-signal direction, Good/Weak grade).")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    var hrText: String { "\(fmt(r.hrPpg, "%.0f")) / \(fmt(r.hrScg, "%.0f")) bpm" }

    func pttText(_ fx: Combo) -> String {
        "\(fmt(fx.pttMedianMs, "%.0f")) ± \(fmt(fx.pttRobustSdMs, "%.0f")) ms (\(fx.valid) beats)"
    }

    var lockText: String {
        let b = r.bestLock
        guard b.isFinite else { return "not enough beats" }
        if r.mode == "table" { return "\(b > 3 ? "yes" : "no") (ratio \(fmt(b)))" }
        let v = b > 6 ? "clear" : (b > 3 ? "weak" : "none")
        return "\(v) (ratio \(fmt(b)))"
    }
}

// MARK: - charts

struct ChartSections: View {
    let p: PlotData

    var body: some View {
        Group {
            Section("Signals, \(fmt(p.x0, "%.0f"))–\(fmt(p.x1, "%.0f")) s") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.label).font(.caption2).foregroundColor(.secondary)
                    Text("Camera light (raw)").font(.caption)
                    TracePlot(values: p.light, start: p.lightStart, dx: p.lightDt, xMin: p.x0, xMax: p.x1,
                              color: .gray, lines: markerLines, height: 60)
                    Text("Finger pulse (orange = \(p.featureName))").font(.caption)
                    TracePlot(values: p.ppg, start: p.start, dx: p.dt, xMin: p.x0, xMax: p.x1,
                              color: .red, lines: featureLines + markerLines, height: 80)
                    Text("Chest SCG (green = AO used, red = AO rejected)").font(.caption)
                    TracePlot(values: p.scg, start: p.start, dx: p.dt, xMin: p.x0, xMax: p.x1,
                              color: .primary, lines: aoLines + markerLines, height: 100)
                }
            }
            if !p.tmpl.isEmpty {
                Section("Chest beats aligned to the finger pulse") {
                    VStack(alignment: .leading, spacing: 6) {
                        TracePlot(values: p.tmpl, start: p.tmplStartMs, dx: p.tmplDtMs, xMin: p.tmplStartMs,
                                  xMax: tmplEnd, color: .primary, lines: tmplLines, lower: p.q1, upper: p.q3, height: 150)
                        HStack {
                            Text("\(fmt(p.tmplStartMs, "%.0f")) ms")
                            Spacer()
                            Text("0 = finger pulse")
                            Spacer()
                            Text("+\(fmt(tmplEnd, "%.0f")) ms")
                        }
                        .font(.caption2).foregroundColor(.secondary)
                        Text(tmplCaption).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Section("Beat by beat") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PTT (ms)\(rangeText(p.ptt, "%.0f"))").font(.caption)
                    ScatterPlot(points: p.ptt, color: .blue)
                    Text("PIR\(rangeText(p.pir, "%.3f"))").font(.caption)
                    ScatterPlot(points: p.pir, color: .purple)
                    Text("Across: time in the recording. A flat band means a stable value.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    var tmplEnd: Double { p.tmplStartMs + p.tmplDtMs * Double(p.tmpl.count) }
    var markerLines: [VLine] { p.markerTimes.map { VLine(x: $0, color: .purple) } }
    var featureLines: [VLine] { p.featureTimes.map { VLine(x: $0, color: .orange) } }
    var aoLines: [VLine] {
        var out: [VLine] = []
        for (x, ok) in Swift.zip(p.aoTimes, p.aoValid) { out.append(VLine(x: x, color: ok ? .green : .red)) }
        return out
    }
    var tmplLines: [VLine] {
        var l = [VLine(x: 0, color: .orange)]
        if let a = p.aoMs { l.append(VLine(x: a, color: .green)) }
        return l
    }
    var tmplCaption: String {
        var s = "Line = median of all beats, shaded = middle 50%."
        if let a = p.aoMs { s += " Green = AO from the template (\(fmt(a, "%.0f")) ms)." }
        s += " A clear wave with a narrow shaded band means the phone is picking up the heartbeat."
        return s
    }

    func rangeText(_ pts: [SeriesPoint], _ f: String) -> String {
        let ys = pts.map { $0.y }.filter { $0.isFinite }
        guard let lo = ys.min(), let hi = ys.max() else { return ": none" }
        return ": \(pts.count) beats, \(fmt(lo, f)) to \(fmt(hi, f))"
    }
}

// MARK: - tap sync charts

struct TapChartSection: View {
    let p: PlotData

    var body: some View {
        Section("Tap signals, whole recording") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Camera frame-to-frame light change (orange = taps seen: \(p.featureTimes.count))").font(.caption)
                TracePlot(values: p.light, start: p.lightStart, dx: p.lightDt, xMin: p.x0, xMax: p.x1,
                          color: .red, lines: p.featureTimes.map { VLine(x: $0, color: .orange) }, height: 90)
                Text("Accelerometer above 5 Hz (green = taps found: \(p.aoTimes.count))").font(.caption)
                TracePlot(values: p.scg, start: p.start, dx: p.dt, xMin: p.x0, xMax: p.x1,
                          color: .primary, lines: p.aoTimes.map { VLine(x: $0, color: .green) }, height: 90)
                HStack {
                    Text("0 s")
                    Spacer()
                    Text("\(fmt(p.x1, "%.0f")) s")
                }
                .font(.caption2).foregroundColor(.secondary)
                Text("Each tap should show as a sharp spike in both traces at the same moment. The small regular spikes in the camera trace are heartbeats; a tap must stand clearly above them to count.")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - full analysis

struct AnalysisSections: View {
    let r: AnalysisResult

    var body: some View {
        Group {
            Section("Result") { VerdictRows(r: r) }
            if let p = r.plot {
                if p.isTap == true { TapChartSection(p: p) } else { ChartSections(p: p) }
            }
            Section("Capture quality") {
                ForEach(r.rates, id: \.name) { s in
                    ResultLine(label: s.name.capitalized,
                               value: "\(fmt(s.rateHz)) Hz, jitter \(fmt(s.jitterMs, "%.2f")) ms, gaps \(s.gaps)", ok: nil)
                }
                ResultLine(label: "Exposure held fixed", value: r.exposureFixed ? "yes" : "no", ok: r.exposureFixed)
                ResultLine(label: "Analysed span", value: "\(fmt(r.spanS)) s", ok: nil)
                if !r.device.isEmpty { ResultLine(label: "Device", value: r.device, ok: nil) }
                if let l = r.lens { ResultLine(label: "Camera lens", value: l, ok: nil) }
                if let tp = r.torchPct {
                    ResultLine(label: "Flash level", value: String(format: "%.0f%%", tp) + ((r.flashRaised ?? false) ? " (raised while positioning)" : ""), ok: nil)
                }
                if let dr = r.lightDriftPct {
                    ResultLine(label: "Finger light drift", value: String(format: "%+.1f%%", dr), ok: r.mode == "tap" ? nil : abs(dr) <= 5)
                }
            }
            Section("Finger pulse colour") {
                ResultLine(label: "Colour used", value: colourUsedText, ok: r.channelPassed)
                ForEach(r.channelQuality ?? [], id: \.channel) { q in
                    VStack(alignment: .leading, spacing: 2) {
                        ResultLine(label: q.channel.uppercased() + (q.channel == r.channel ? " (used)" : ""),
                                   value: q.passed ? "clean pulse" : "failed", ok: q.passed)
                        Text(qualityText(q)).font(.caption2).foregroundColor(.secondary)
                        if !q.passed && !q.reason.isEmpty {
                            Text(q.reason).font(.caption2).foregroundColor(.orange)
                        }
                    }
                }
                if r.channelQuality == nil {
                    ForEach(r.channels, id: \.channel) { c in
                        ResultLine(label: c.channel.uppercased() + (c.channel == r.channel ? " (used)" : ""),
                                   value: "mean \(fmt(c.mean, "%.0f")), pulse \(fmt(c.pulsatilityPct, "%.2f"))%, clarity \(fmt(c.peakRatio))",
                                   ok: nil)
                    }
                }
                Text("A real heartbeat: enough clean beats, one steady rhythm, steady beat timing, beats that look alike, and the same beats seen in red and green. Noise fails these.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            if !r.locks.isEmpty {
                Section("Heartbeat check per chest band") {
                    ForEach(Array(r.locks.enumerated()), id: \.offset) { item in
                        ResultLine(label: lockLabel(item.element), value: lockValue(item.element), ok: nil)
                    }
                    Text("Ratio = beat-aligned chest average vs averages at random times. Above 6 clear, 3 to 6 weak, below 3 none. 'Before' looks only 60–400 ms before the finger pulse, where the heart's opening beat is searched. The out-of-chest axis there decides the verdict.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("All PTT combinations") {
                    DisclosureGroup("Ranked by stability (\(r.ranked.count))") {
                        ForEach(r.ranked) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Analyzer.methodName(c.method)) · \(c.band) · \(c.axis) · \(Analyzer.featureName(c.feature))")
                                    .font(.caption.bold())
                                Text("PTT \(fmt(c.pttMedianMs)) ms, robust SD \(fmt(c.pttRobustSdMs)), valid \(c.valid)/\(c.beats), split-half \(fmt(c.splitHalfMs, "%+.1f"))")
                                    .font(.caption)
                            }
                        }
                    }
                    Text("Picking the best row overfits. Compare sessions with the fixed method; use this list only to choose a method once, from pilot sessions.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Section("Full report") {
                DisclosureGroup("Show text") {
                    Text(r.text).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
    }
}

extension AnalysisSections {
    var colourUsedText: String {
        let n = ColourProfile.name(r.channel)
        switch r.channelSource {
        case "locked": return "\(n) (saved)"
        case "auto": return "\(n) (chosen automatically)"
        case "fallback": return "\(n) (none passed)"
        default: return n
        }
    }

    func qualityText(_ q: ChannelQuality) -> String {
        let ag = q.agreementPct.map { String(format: "%.0f%%", $0) } ?? "not checked"
        return "brightness \(fmt(q.mean, "%.0f")), clean beats \(q.okBeats)/\(q.beats), rhythm \(fmt(q.peakRatio)), timing \(fmt(q.ibiCvPct))%, shape \(fmt(q.shapeCorr, "%.2f")), match \(ag)"
    }

    func lockLabel(_ l: BandLock) -> String { "\(l.band) · \(Analyzer.axisName(l.axis))" }

    func lockValue(_ l: BandLock) -> String {
        var s = "before \(fmt(l.ratio))"
        if let a = l.ratioAll { s += ", whole \(fmt(a))" }
        return s
    }
}

struct AnalysisDetailView: View {
    let r: AnalysisResult

    var body: some View {
        Form { AnalysisSections(r: r) }
            .navigationTitle("Analysis")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - saved recordings

struct SessionDetailView: View {
    @ObservedObject var rec: Recorder
    let folder: URL
    @State private var result: AnalysisResult?
    @State private var running = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Button(buttonTitle) { run() }.disabled(running)
                Button("Share this recording (zip)") { rec.share(folder) }
                if let e = error { Text(e).foregroundColor(.red).font(.callout) }
            }
            if let r = result { AnalysisSections(r: r) }
        }
        .navigationTitle(folder.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded {
                loaded = true
                result = Analyzer.loadSaved(folder)
            }
        }
    }

    var buttonTitle: String {
        if running { return "Analysing…" }
        return result == nil ? "Analyse this recording" : "Re-analyse"
    }

    @MainActor private func run() {
        running = true
        error = nil
        Task { @MainActor in
            let r = await Analyzer.analyzeAsync(folder: folder)
            switch r {
            case .success(let a): result = a
            case .failure(let e): error = e.localizedDescription
            }
            running = false
        }
    }
}

struct CompareItem: Identifiable {
    let url: URL
    var result: AnalysisResult?
    var id: String { url.lastPathComponent }
}

struct CompareRow: View {
    let item: CompareItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.url.lastPathComponent).font(.callout)
            Text(detail).font(.caption).foregroundColor(.secondary)
        }
    }

    var detail: String {
        guard let r = item.result else { return "not analysed yet" }
        if let t = r.tap { return "tap: offset \(fmt(t.offsetMedianMs)) ms, SD \(fmt(t.offsetSdMs)) ms, \(t.paired) taps" }
        var s = (r.isFlagged ? "⚑ flagged · " : "") + "\(r.mode)"
        if let g = r.grade { s += g.good ? " · Good" : " · Weak" }
        if r.placement == "diaphragm" { s += " · diaphragm" }
        s += " · HR \(fmt(r.hrPpg, "%.0f")) · ratio \(fmt(r.bestLock))" + (r.version < 3 ? " (old analysis)" : "")
        if r.mode == "chest", let f = r.fixed {
            s += " · PTT \(fmt(f.pttMedianMs, "%.0f")) ± \(fmt(f.pttRobustSdMs, "%.0f")) ms"
        }
        if r.pirMedian.isFinite { s += " · PIR \(fmt(r.pirMedian, "%.3f"))" }
        return s
    }
}

struct PlacementSummary: View {
    let name: String
    let rows: [AnalysisResult]

    var body: some View {
        let ptt = rows.filter { $0.grade?.good == true }.compactMap { $0.grade?.pttMedianMs }.filter { $0.isFinite }
        let locks = rows.map { $0.bestLock }.filter { $0.isFinite }
        let good = rows.filter { $0.grade?.good == true }.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.callout.bold())
            Text("\(rows.count) recordings, \(good) Good · heartbeat ratio (median) \(fmt(DSP.median(locks)))")
                .font(.caption)
            Text("PTT (Good only): mean \(fmt(DSP.mean(ptt), "%.0f")) ms, SD \(fmt(DSP.sampleSD(ptt))) ms")
                .font(.caption)
        }
    }
}

struct CompareView: View {
    @ObservedObject var rec: Recorder
    @State private var items: [CompareItem] = []
    @State private var running = false
    @State private var progress = ""

    var results: [AnalysisResult] { items.compactMap { $0.result } }
    var currentSetup: Int { ColourProfile.setup }
    var chestAll: [AnalysisResult] { results.filter { $0.mode == "chest" } }
    /// Recordings from the current finger-colour choice that aren't flagged.
    var chestUsable: [AnalysisResult] {
        chestAll.filter { !$0.isFlagged && (currentSetup == 0 || $0.colourSetup == currentSetup) && $0.version >= 3 }
    }
    /// Main results: lower breastbone only.
    var chest: [AnalysisResult] { chestUsable.filter { ($0.placement ?? "sternum") == "sternum" } }
    /// Version 2: only recordings graded Good count for PTT.
    var detected: [AnalysisResult] { chest.filter { $0.grade?.good == true } }
    var oldCount: Int { chestAll.filter { $0.version < 3 }.count }

    func placementRows(_ p: String) -> [AnalysisResult] { chestUsable.filter { ($0.placement ?? "sternum") == p } }
    func goodPTT(_ rs: [AnalysisResult]) -> [Double] {
        rs.filter { $0.grade?.good == true }.compactMap { $0.grade?.pttMedianMs }.filter { $0.isFinite }
    }
    var placementDiff: Double { DSP.mean(goodPTT(placementRows("diaphragm"))) - DSP.mean(goodPTT(placementRows("sternum"))) }
    var pttMedians: [Double] { detected.compactMap { $0.fixed?.pttMedianMs }.filter { $0.isFinite } }
    var pttWithin: [Double] { detected.compactMap { $0.fixed?.pttRobustSdMs }.filter { $0.isFinite } }
    var tapOffsets: [Double] { results.compactMap { $0.tap?.offsetMedianMs }.filter { $0.isFinite } }
    var tableLocks: [Double] { results.filter { $0.mode == "table" }.map { $0.bestLock }.filter { $0.isFinite } }

    var body: some View {
        List {
            Section {
                Button(running ? progress : "Analyse recordings not yet analysed") { runAll(everything: false) }.disabled(running)
                Button("Re-analyse all recordings") { runAll(everything: true) }.disabled(running)
                Text("After an app update, re-analyse so every recording uses the same method.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Chest + finger at rest") {
                ResultLine(label: "Graded Good", value: "\(detected.count) of \(chest.count) recordings", ok: nil)
                if oldCount > 0 {
                    Text("\(oldCount) chest recording(s) analysed with an older version: tap Re-analyse all recordings.")
                        .font(.caption).foregroundColor(.orange)
                }
                if chestAll.count - oldCount > chestUsable.count {
                    Text("\(chestAll.count - oldCount - chestUsable.count) chest recording(s) not counted: flagged, or from an earlier finger-colour choice.")
                        .font(.caption).foregroundColor(.orange)
                }
                ResultLine(label: "PTT, mean of recordings", value: "\(fmt(DSP.mean(pttMedians), "%.0f")) ms", ok: nil)
                ResultLine(label: "PTT spread between recordings (SD)", value: "\(fmt(DSP.sampleSD(pttMedians))) ms", ok: nil)
                ResultLine(label: "Typical spread within a recording", value: "\(fmt(DSP.median(pttWithin))) ms", ok: nil)
                Text("Lower breastbone only, fixed method, only recordings graded Good. Pass marks set in advance: Good in at least 4 of 5, spread within each 10 ms or less, spread between recordings 15 ms or less.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Placement test") {
                ForEach(["sternum", "diaphragm"], id: \.self) { p in
                    PlacementSummary(name: Analyzer.placementName(p).capitalized, rows: placementRows(p))
                }
                ResultLine(label: "PTT difference (diaphragm − breastbone)", value: "\(fmt(placementDiff, "%+.0f")) ms", ok: nil)
                Text("If the diaphragm area works, it should give mostly Good recordings and a PTT within a few ms of the breastbone. A clearly different PTT means it picks up something else (for example the pulse of the main artery). Judgement, not proof: needs several recordings at each place.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Tap sync") {
                ResultLine(label: "Repeats", value: "\(tapOffsets.count)", ok: nil)
                ResultLine(label: "Offset, mean of repeats", value: "\(fmt(DSP.mean(tapOffsets))) ms", ok: nil)
                ResultLine(label: "Offset spread between repeats (SD)", value: "\(fmt(DSP.sampleSD(tapOffsets))) ms", ok: nil)
            }
            Section("Table control") {
                ResultLine(label: "Highest beat-locked ratio", value: tableLocks.isEmpty ? "–" : fmt(tableLocks.max() ?? .nan),
                           ok: tableLocks.isEmpty ? nil : (tableLocks.max() ?? 0) <= 3)
                Text("Should stay below 3. Higher means the finger pulse leaks into the accelerometer.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Recordings") {
                ForEach(items) { it in
                    NavigationLink(destination: SessionDetailView(rec: rec, folder: it.url)) { CompareRow(item: it) }
                }
            }
        }
        .navigationTitle("Compare sessions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
    }

    @MainActor private func reload() {
        guard !running else { return }
        items = SessionStore.list().map { CompareItem(url: $0, result: Analyzer.loadSaved($0)) }
    }

    @MainActor private func runAll(everything: Bool) {
        running = true
        Task { @MainActor in
            let todo = items.indices.filter { everything || items[$0].result == nil }
            var failed = 0
            for (k, i) in todo.enumerated() {
                progress = "Analysing \(k + 1) of \(todo.count)…"
                let r = await Analyzer.analyzeAsync(folder: items[i].url)
                if case .success(let a) = r {
                    if i < items.count { items[i].result = a }
                } else {
                    failed += 1
                }
            }
            running = false
            progress = ""
            if failed > 0 { progress = "" }
        }
    }
}
