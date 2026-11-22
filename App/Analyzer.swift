import Foundation

// MARK: - Result types (saved as analysis/summary.json inside each recording)

struct ChannelInfo: Codable {
    var channel = ""
    var mean = 0.0
    var pulsatilityPct = 0.0
    var peakRatio = 0.0
}

/// Finger-pulse quality for one colour: is this a real, clean heartbeat and not noise?
struct ChannelQuality: Codable {
    var channel = ""
    var mean = 0.0                // brightness 0-255
    var beats = 0                 // pulses found
    var okBeats = 0               // pulses with normal size and timing
    var peakRatio = 0.0           // rhythm clarity (one steady heart rate)
    var ibiCvPct = Double.nan     // beat-to-beat timing variation, %
    var shapeCorr = Double.nan    // how alike the beats look (1 = identical)
    var agreementPct: Double?     // % of beats also found in the other colour (nil = not checked)
    var passed = false
    var reason = ""
}

struct StreamRate: Codable {
    var name = ""
    var n = 0
    var rateHz = 0.0
    var jitterMs = 0.0
    var gaps = 0
    var longestGapMs = 0.0
}

struct BandLock: Codable {
    var band = ""
    var ratio = Double.nan          // before the pulse only (60-400 ms before the finger-pulse foot)
    var snrDb = Double.nan
    var verdict = ""
    var axis: String?              // "dv" = out of the chest (-z), "pca" = best direction. nil = analysed before 0.3.2
    var ratioAll: Double?          // whole window (500 ms before to 100 ms after the foot)
}

struct Combo: Codable, Identifiable {
    var method = ""
    var band = ""
    var axis = ""
    var feature = ""
    var beats = 0
    var valid = 0
    var yieldPct = 0.0
    var hrScg = Double.nan
    var pttMedianMs = Double.nan
    var pttIqrMs = Double.nan
    var pttRobustSdMs = Double.nan
    var splitHalfMs = Double.nan
    var key: String { "\(method)|\(band)|\(axis)|\(feature)" }
    var id: String { key }
}

struct TapResult: Codable {
    var accTaps = 0
    var ppgEvents = 0
    var paired = 0
    var offsetMedianMs = Double.nan
    var offsetSdMs = Double.nan
}

struct SeriesPoint: Codable {
    var x = 0.0
    var y = 0.0
}

struct PlotData: Codable {
    var isTap: Bool?
    var label = ""
    var featureName = ""
    var x0 = 0.0                 // s, window start (relative to analysed start)
    var x1 = 10.0
    var lightStart = 0.0
    var lightDt = 0.01
    var light: [Double] = []     // raw camera light (chosen channel)
    var start = 0.0
    var dt = 0.005
    var ppg: [Double] = []       // PPG volume (filtered)
    var scg: [Double] = []       // SCG on the chosen axis
    var featureTimes: [Double] = []
    var aoTimes: [Double] = []
    var aoValid: [Bool] = []
    var markerTimes: [Double] = []
    var tmplStartMs = -500.0
    var tmplDtMs = 2.0
    var tmpl: [Double] = []
    var q1: [Double] = []
    var q3: [Double] = []
    var aoMs: Double?
    var ptt: [SeriesPoint] = []
    var pir: [SeriesPoint] = []
}

struct AnalysisResult: Codable {
    var version = 2
    var lens: String?
    var torchPct: Double?
    var lightDriftPct: Double?
    var session = ""
    var mode = ""
    var device = ""
    var created = ""
    var spanS = 0.0
    var rates: [StreamRate] = []
    var isoRange: [Double] = []
    var expRange: [Double] = []
    var exposureFixed = true
    var channels: [ChannelInfo] = []
    var channel = ""
    var hrPpg = Double.nan
    var nBeats = 0
    var nPpgOk = 0
    var pirMedian = Double.nan
    var pirCv = Double.nan
    var gravity: [Double] = []
    var locks: [BandLock] = []
    var scgDetected: Bool?
    var hrScg = Double.nan
    var ranked: [Combo] = []
    var fixed: Combo?
    var tap: TapResult?
    var plot: PlotData?
    var warnings: [String] = []
    var notes: [String]?
    var flags: [String]?
    var channelQuality: [ChannelQuality]?
    var channelSource: String?    // "locked" (saved colour), "auto" (chosen now), "fallback" (none passed)
    var channelPassed: Bool?
    var colourSetup: Int?
    var flashRaised: Bool?
    var text = ""

    var isFlagged: Bool { !(flags ?? []).isEmpty }

    /// The ratio decisions use: out-of-chest axis, before the pulse (older results: whatever was saved).
    var bestLock: Double {
        let v = locks.filter { $0.axis == nil || $0.axis == "dv" }.map { $0.ratio }.filter { $0.isFinite }
        return v.max() ?? .nan
    }

    /// Highest ratio in any direction and either window (shows any finger-pulse movement at all).
    var anyLock: Double {
        var v: [Double] = []
        for l in locks {
            if l.ratio.isFinite { v.append(l.ratio) }
            if let a = l.ratioAll, a.isFinite { v.append(a) }
        }
        return v.max() ?? .nan
    }
}

enum AnalysisError: LocalizedError {
    case missing(String), tooShort(Double), badRate(String)
    var errorDescription: String? {
        switch self {
        case .missing(let f): return "Recording file missing or unreadable: \(f)"
        case .tooShort(let s):
            return String(format: "Recording too short to analyse (%.1f s usable, need at least 10 s).", s)
        case .badRate(let s): return "Could not work out the \(s) sampling rate."
        }
    }
}

struct SessionData {
    var name = ""
    var mode = ""
    var device = ""
    var os = ""
    var lens = "main"
    var torchPct: Double?
    var lockedChannel: String?
    var colourSetup: Int?
    var flags: [String] = []
    var flashRaised: Bool?
    var ppg: [String: [Double]] = [:]
    var ppgRecord: [Bool] = []
    var acc: [String: [Double]] = [:]
    var accRecord: [Bool] = []
    var markers: [Double] = []
}

struct Beat {
    var peakI = 0
    var footI = 0
    var tPeak = 0.0
    var tFoot = 0.0
    var maxSlope = 0.0
    var tangentFoot = Double.nan
    var apgPeak = 0.0
    var amp = 0.0
    var pir = Double.nan
    var ibi = Double.nan
    var sat = 0.0
    var ok = false

    func time(_ f: String) -> Double {
        switch f {
        case "apg_peak": return apgPeak
        case "tangent_foot": return tangentFoot
        default: return maxSlope
        }
    }
}

// MARK: - Analyzer (port of analysis/hc_analyze.py)

enum Analyzer {
    static let fsHi = 1000.0
    static let ppgLo = 0.5, ppgHi = 10.0
    static let scgBands: [(Double, Double)] = [(1, 20), (5, 40)]
    static let pttLo = 0.060, pttHi = 0.400
    static let minValidBeats = 15
    static let edgeTrim = 1.0
    static let features = ["apg_peak", "tangent_foot", "max_slope"]
    static let methods = ["rule", "ensemble", "scg_first"]
    static let fixedMethod = "ensemble", fixedAxis = "dv", fixedFeature = "tangent_foot"

    static func featureName(_ f: String) -> String {
        switch f {
        case "apg_peak": return "APG peak"
        case "tangent_foot": return "tangent foot"
        default: return "max slope"
        }
    }

    static func lockVerdict(_ x: Double) -> String { x > 6 ? "clear" : (x > 3 ? "weak" : "none") }

    static func axisName(_ a: String?) -> String { (a ?? "pca") == "dv" ? "out-of-chest" : "best direction" }

    static func methodName(_ m: String) -> String {
        switch m {
        case "rule": return "per-beat rule"
        case "ensemble": return "beat-averaged template"
        default: return "SCG-first"
        }
    }

    // MARK: loading

    static func readCSV(_ url: URL) throws -> (cols: [String: [Double]], phase: [String]) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw AnalysisError.missing(url.lastPathComponent)
        }
        let lines = text.split(whereSeparator: { $0.isNewline })
        guard let header = lines.first else { throw AnalysisError.missing(url.lastPathComponent) }
        let names = header.split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let phaseIdx = names.firstIndex(of: "phase")
        let labelIdx = names.firstIndex(of: "label")
        var data = [[Double]](repeating: [], count: names.count)
        for k in 0..<names.count { data[k].reserveCapacity(lines.count) }
        var phase: [String] = []
        phase.reserveCapacity(lines.count)
        for line in lines.dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            if f.count < names.count { continue }
            for k in 0..<names.count {
                if k == phaseIdx {
                    phase.append(String(f[k]))
                } else if k != labelIdx {
                    data[k].append(Double(String(f[k])) ?? .nan)
                }
            }
        }
        var cols: [String: [Double]] = [:]
        for (k, n) in names.enumerated() where k != phaseIdx && k != labelIdx { cols[n] = data[k] }
        return (cols, phase)
    }

    static func load(_ folder: URL) throws -> SessionData {
        var d = SessionData()
        d.name = folder.lastPathComponent
        let meta = SessionStore.readMeta(folder: folder)
        d.mode = meta["mode"] as? String ?? (d.name.components(separatedBy: "_").last ?? "")
        d.device = meta["device_model"] as? String ?? ""
        d.os = meta["os_version"] as? String ?? ""
        d.lens = meta["lens"] as? String ?? "main"
        if let cam = meta["camera"] as? [String: Any], let tl = cam["torch_level"] as? Double { d.torchPct = 100 * tl }
        d.lockedChannel = meta["ppg_channel_locked"] as? String
        d.colourSetup = meta["colour_setup"] as? Int
        d.flags = meta["flags"] as? [String] ?? []
        d.flashRaised = meta["flash_raised"] as? Bool
        let p = try readCSV(folder.appendingPathComponent("ppg.csv"))
        d.ppg = p.cols
        let pn = p.cols["t"]?.count ?? 0
        d.ppgRecord = p.phase.count == pn ? p.phase.map { $0 == "record" } : [Bool](repeating: true, count: pn)
        let a = try readCSV(folder.appendingPathComponent("acc.csv"))
        d.acc = a.cols
        let an = a.cols["t"]?.count ?? 0
        d.accRecord = a.phase.count == an ? a.phase.map { $0 == "record" } : [Bool](repeating: true, count: an)
        if let m = try? readCSV(folder.appendingPathComponent("markers.csv")) { d.markers = m.cols["t"] ?? [] }
        guard pn > 50, an > 50 else { throw AnalysisError.missing("ppg.csv / acc.csv (too few rows)") }
        return d
    }

    static func pickRows(_ v: [Double], _ mask: [Bool]) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(v.count)
        for i in 0..<min(v.count, mask.count) where mask[i] { out.append(v[i]) }
        return out
    }

    static func rateReport(_ t: [Double], _ name: String) -> StreamRate {
        let dt = DSP.diff(t)
        let med = DSP.median(dt)
        var r = StreamRate()
        r.name = name
        r.n = t.count
        r.rateHz = med > 0 ? 1 / med : .nan
        r.jitterMs = 1000 * DSP.robustSD(dt)
        r.gaps = dt.filter { $0 > 1.5 * med }.count
        r.longestGapMs = 1000 * (dt.max() ?? .nan)
        return r
    }

    // MARK: saved results

    static func analysisDir(_ folder: URL) -> URL { folder.appendingPathComponent("analysis", isDirectory: true) }

    static func save(_ r: AnalysisResult, _ folder: URL) throws {
        let dir = analysisDir(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(r).write(to: dir.appendingPathComponent("summary.json"))
        try r.text.write(to: dir.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    static func loadSaved(_ folder: URL) -> AnalysisResult? {
        guard let d = try? Data(contentsOf: analysisDir(folder).appendingPathComponent("summary.json")) else { return nil }
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try? dec.decode(AnalysisResult.self, from: d)
    }

    static func analyzeAsync(folder: URL) async -> Result<AnalysisResult, Error> {
        await Task.detached(priority: .userInitiated) { () -> Result<AnalysisResult, Error> in
            do {
                return .success(try Analyzer.analyze(folder: folder))
            } catch {
                return .failure(error)
            }
        }.value
    }

    // MARK: PPG

    struct PPG {
        var t: [Double] = []
        var v: [Double] = []
        var L: [Double] = []
        var sat: [Double] = []
        var fs = 0.0
        var hrHz = Double.nan
        var channel = "g"
        var info: [ChannelInfo] = []
        var rawT: [Double] = []
        var rawL: [Double] = []
    }

    static func ppgProcess(t: [Double], cols: [String: [Double]], fs: Double, t0: Double, t1: Double,
                           force: String? = nil) -> PPG {
        var P = PPG()
        P.fs = fs
        var best = "r", bestScore = -1.0
        for c in ["r", "g", "b"] {
            guard let col = cols[c] else { continue }
            let L = DSP.uniform(t, col, fs: fs, t0: t0, t1: t1).x
            let ac = DSP.bandpass(L, fs: fs, lo: 0.7, hi: 3.5)
            let dc = DSP.mean(L)
            let sd = DSP.std(ac)
            let puls = (dc > 1 && sd.isFinite) ? sd / dc : 0
            let peak = sd > 0 ? DSP.spectralPeakRatio(ac, fs: fs, lo: 0.7, hi: 3.5) : 0
            P.info.append(ChannelInfo(channel: c, mean: dc, pulsatilityPct: 100 * puls, peakRatio: peak))
            let ok = dc > 5 && dc < 250
            let score = ok ? puls * log1p(peak) : 0
            if score > bestScore {
                best = c
                bestScore = score
            }
        }
        if let f = force, cols[f] != nil { best = f }
        P.channel = best
        let u = DSP.uniform(t, cols[best] ?? [], fs: fs, t0: t0, t1: t1)
        let L = u.x
        let satRaw: [Double]
        if let s = cols["sat_any"] {
            satRaw = DSP.uniform(t, s, fs: fs, t0: t0, t1: t1).x
        } else {
            satRaw = [Double](repeating: 0, count: L.count)
        }
        let bp = DSP.bandpass(L, fs: fs, lo: ppgLo, hi: ppgHi)
        P.hrHz = DSP.dominantHR(bp.map { -$0 }, fs: fs)
        P.v = DSP.resampleLanczos(bp, fsIn: fs, fsOut: fsHi).map { -$0 }     // more blood = up
        P.L = DSP.resampleLanczos(DSP.bandpass(L, fs: fs, lo: 0, hi: ppgHi), fsIn: fs, fsOut: fsHi)
        var th = [Double](repeating: 0, count: P.v.count)
        for i in 0..<th.count { th[i] = t0 + Double(i) / fsHi }
        P.t = th
        P.sat = DSP.interp(th, u.t, satRaw)
        P.rawT = u.t
        P.rawL = L
        return P
    }

    /// Quality of one colour at the camera's own rate. Returns the quality and the times of the clean pulses.
    static func channelQuality(t: [Double], col: [Double], ch: String, fs: Double, t0: Double, t1: Double)
        -> (ChannelQuality, [Double]) {
        var q = ChannelQuality()
        q.channel = ch
        let L = DSP.uniform(t, col, fs: fs, t0: t0, t1: t1).x
        q.mean = DSP.mean(L)
        guard L.count > Int(10 * fs), q.mean.isFinite else { return (q, []) }
        let ac = DSP.bandpass(L, fs: fs, lo: 0.7, hi: 3.5)
        q.peakRatio = DSP.std(ac) > 0 ? DSP.spectralPeakRatio(ac, fs: fs, lo: 0.7, hi: 3.5) : 0
        let v = DSP.bandpass(L, fs: fs, lo: 0.5, hi: 10).map { -$0 }
        let hr = DSP.dominantHR(v, fs: fs)
        guard hr.isFinite, hr > 0 else { return (q, []) }
        let T = 1 / hr
        let pk = DSP.findPeaks(v, distance: Int(0.6 * T * fs), wl: Int(1.5 * T * fs), minRelProm: 0.3)
        var feet: [Int] = []
        var peaks: [Int] = []
        for i in pk {
            let a = max(0, i - Int(0.5 * T * fs))
            if i - a < 3 { continue }
            let f = DSP.argmin(v, a, i)
            if i - f < 2 { continue }
            feet.append(f)
            peaks.append(i)
        }
        q.beats = feet.count
        guard feet.count >= 5 else { return (q, []) }
        var amps: [Double] = []
        for k in 0..<feet.count { amps.append(v[peaks[k]] - v[feet[k]]) }
        var ibi: [Double] = []
        for k in 0..<(feet.count - 1) { ibi.append(Double(feet[k + 1] - feet[k]) / fs) }
        let medA = DSP.median(amps), medI = DSP.median(ibi)
        var ok = [Bool](repeating: false, count: feet.count)
        for k in 0..<feet.count {
            let ib = k < ibi.count ? ibi[k] : Double.nan
            ok[k] = amps[k] > 0.4 * medA && amps[k] < 2.5 * medA && (!ib.isFinite || abs(ib - medI) < 0.25 * medI)
        }
        q.okBeats = ok.filter { $0 }.count
        q.ibiCvPct = medI > 0 ? 100 * DSP.robustSD(ibi) / medI : .nan
        // beat shape: each clean beat (normalised) compared with the typical beat
        let pre = Int(0.1 * T * fs), post = Int(0.6 * T * fs)
        var segs: [[Double]] = []
        for k in 0..<feet.count where ok[k] {
            let f = feet[k]
            if f - pre < 0 || f + post > v.count { continue }
            let s = Array(v[(f - pre)..<(f + post)])
            let m = DSP.mean(s), sd = DSP.std(s)
            if sd > 0 { segs.append(s.map { ($0 - m) / sd }) }
        }
        if segs.count >= 5 {
            let tm = DSP.columnMedian(segs)
            let tmu = DSP.mean(tm), tsd = DSP.std(tm)
            if tsd > 0 {
                var cs: [Double] = []
                for s in segs {
                    var c = 0.0
                    let n = min(s.count, tm.count)
                    for j in 0..<n { c += s[j] * (tm[j] - tmu) / tsd }
                    cs.append(c / Double(n))
                }
                q.shapeCorr = DSP.median(cs)
            }
        }
        var times: [Double] = []
        for k in 0..<feet.count where ok[k] { times.append(t0 + Double(feet[k]) / fs) }
        return (q, times)
    }

    /// Pass/fail rules for a colour. Thresholds are judgement calls, checked on the first real recordings.
    static func judge(_ q: inout ChannelQuality) {
        var why: [String] = []
        if !(q.mean >= 10) { why.append("too dark") }
        if q.mean > 245 { why.append("too bright") }
        if q.okBeats < 15 {
            why.append("too few clean beats")
        } else if Double(q.okBeats) < 0.6 * Double(q.beats) {
            why.append("many irregular beats")
        }
        if !(q.peakRatio >= 5) { why.append("heartbeat rhythm not clear") }
        if !(q.ibiCvPct <= 15) { why.append("beat timing irregular") }
        if !(q.shapeCorr >= 0.8) { why.append("beat shape inconsistent") }
        if let ag = q.agreementPct, ag < 70 { why.append("beats don't match the other colour") }
        q.passed = why.isEmpty
        q.reason = why.joined(separator: ", ")
    }

    /// Quality of every colour, including whether red and green find the same beats.
    static func assessColours(t: [Double], cols: [String: [Double]], fs: Double, t0: Double, t1: Double) -> [ChannelQuality] {
        var qs: [ChannelQuality] = []
        var feet: [String: [Double]] = [:]
        for c in ["r", "g", "b"] {
            guard let col = cols[c] else { continue }
            let res = channelQuality(t: t, col: col, ch: c, fs: fs, t0: t0, t1: t1)
            var q = res.0
            judge(&q)
            qs.append(q)
            feet[c] = res.1
        }
        for i in qs.indices where qs[i].channel == "r" || qs[i].channel == "g" {
            let other = qs[i].channel == "r" ? "g" : "r"
            guard let j = qs.firstIndex(where: { $0.channel == other }), qs[j].passed,
                  let fo = feet[other], let fm = feet[qs[i].channel], !fm.isEmpty else { continue }
            var hit = 0
            for x in fm where fo.contains(where: { abs($0 - x) <= 0.05 }) { hit += 1 }
            qs[i].agreementPct = 100 * Double(hit) / Double(fm.count)
        }
        for i in qs.indices { judge(&qs[i]) }
        return qs
    }

    /// Best colour among those that passed: most consistent beat shape; if close (within 0.02),
    /// the larger share of clean beats; if that is close too (within 2 points), the clearer rhythm.
    static func bestColour(_ qs: [ChannelQuality]) -> String? {
        func cleanShare(_ q: ChannelQuality) -> Double { q.beats > 0 ? Double(q.okBeats) / Double(q.beats) : 0 }
        let passing = qs.filter { $0.passed }.sorted { a, b in
            if abs(a.shapeCorr - b.shapeCorr) > 0.02 { return a.shapeCorr > b.shapeCorr }
            let ca = cleanShare(a), cb = cleanShare(b)
            if abs(ca - cb) > 0.02 { return ca > cb }
            return a.peakRatio > b.peakRatio
        }
        return passing.first?.channel
    }

    static func ppgBeats(_ P: PPG) -> [Beat] {
        let v = P.v, t = P.t, fs = fsHi
        guard P.hrHz.isFinite, P.hrHz > 0, v.count > 100, t.count == v.count else { return [] }
        let T = 1 / P.hrHz
        let d1 = DSP.gradient(v, fs: fs)
        let d2 = DSP.gradient(d1, fs: fs)
        let pk = DSP.findPeaks(v, distance: Int(0.6 * T * fs), wl: Int(1.5 * T * fs), minRelProm: 0.3)
        var B: [Beat] = []
        for i in pk {
            let a = max(0, i - Int(0.5 * T * fs))
            if i - a < 10 { continue }
            let foot = DSP.argmin(v, a, i)
            if i - foot < 5 { continue }
            let ms = DSP.argmax(d1, foot, i)
            var bt = Beat()
            bt.peakI = i
            bt.footI = foot
            bt.tPeak = t[i]
            bt.tFoot = t[foot]
            bt.maxSlope = t[ms]
            bt.tangentFoot = d1[ms] > 0 ? t[ms] - (v[ms] - v[foot]) / d1[ms] : .nan
            let b = max(0, foot - Int(0.08 * fs))
            bt.apgPeak = t[DSP.argmax(d2, b, ms + 1)]
            bt.amp = v[i] - v[foot]
            B.append(bt)
        }
        guard B.count >= 3 else { return B }
        let L = P.L
        let w = Int(0.03 * fs)
        func wmax(_ c: Int) -> Double {
            let a = max(0, c - w), b = min(L.count, c + w)
            return b > a ? (L[a..<b].max() ?? .nan) : .nan
        }
        func wmin(_ c: Int) -> Double {
            let a = max(0, c - w), b = min(L.count, c + w)
            return b > a ? (L[a..<b].min() ?? .nan) : .nan
        }
        for k in 0..<B.count {
            if k + 1 < B.count {
                let l1 = wmax(B[k].footI), l2 = wmax(B[k + 1].footI), lp = wmin(B[k].peakI)
                B[k].pir = lp > 0 ? (l1 + l2) / (2 * lp) : .nan
                B[k].ibi = B[k + 1].tPeak - B[k].tPeak
            }
            let a = max(0, B[k].footI), b = min(P.sat.count, B[k].peakI + 1)
            B[k].sat = b > a ? (P.sat[a..<b].max() ?? 0) : 0
        }
        let medIbi = DSP.median(B.map { $0.ibi })
        let medAmp = DSP.median(B.map { $0.amp })
        for k in 0..<B.count {
            let b = B[k]
            let ibiOk = !b.ibi.isFinite || abs(b.ibi - medIbi) < 0.25 * medIbi
            B[k].ok = b.sat < 0.02 && b.amp > 0.4 * medAmp && b.amp < 2.5 * medAmp && ibiOk
        }
        return B
    }

    // MARK: SCG

    struct SCGSet {
        var bands: [String] = []
        var sig: [String: [Double]] = [:]
        var grav = [0.0, 0.0, 0.0]
        var pcDir: [String: [Double]] = [:]
    }

    static func bandKey(_ lo: Double, _ hi: Double) -> String { String(format: "%g-%gHz", lo, hi) }

    static func scgAxes(t: [Double], cols: [String: [Double]], fs: Double, t0: Double, t1: Double) -> SCGSet {
        var S = SCGSet()
        var raw: [[Double]] = []
        for a in ["x", "y", "z"] { raw.append(DSP.uniform(t, cols[a] ?? [], fs: fs, t0: t0, t1: t1).x) }
        S.grav = raw.map { DSP.mean($0) }
        for (lo, hi) in scgBands {
            let hiEff = min(hi, 0.45 * fs)
            let key = bandKey(lo, hiEff)
            S.bands.append(key)
            let nat = raw.map { DSP.bandpass($0, fs: fs, lo: lo, hi: hiEff) }
            var pc = DSP.topEigenvector3(DSP.cov3(nat))
            if pc[2] > 0 { pc = pc.map { -$0 } }      // align with -z (screen against chest => -z is out of the chest)
            S.pcDir[key] = pc
            let up = nat.map { DSP.resampleLanczos($0, fsIn: fs, fsOut: fsHi) }
            let n = up.map { $0.count }.min() ?? 0
            var dv = [Double](repeating: 0, count: n)
            var pca = [Double](repeating: 0, count: n)
            for i in 0..<n {
                dv[i] = -up[2][i]
                pca[i] = pc[0] * up[0][i] + pc[1] * up[1][i] + pc[2] * up[2][i]
            }
            S.sig[key + "|dv"] = dv
            S.sig[key + "|pca"] = pca
        }
        return S
    }

    static func scgHR(_ s: [Double]) -> (hrHz: Double, env: [Double]) {
        let env = DSP.movavg(DSP.analyticEnv(s), Int(0.05 * fsHi))
        let ds = Int(fsHi) / 50
        var sub: [Double] = []
        sub.reserveCapacity(env.count / ds + 1)
        var i = 0
        while i < env.count { sub.append(env[i]); i += ds }
        return (DSP.dominantHR(sub, fs: fsHi / Double(ds)), env)
    }

    /// Seismo-style: IM = most prominent negative peak (earlier one if >= 90%), AO = next positive peak.
    static func ruleAO(_ seg: [Double], rel: Double = 0.05) -> Int? {
        guard seg.count >= 10, let mx = seg.max(), let mn = seg.min() else { return nil }
        let rng = mx - mn
        let negSeg = seg.map { -$0 }
        var neg: [Int] = []
        var pr: [Double] = []
        for i in DSP.localMax(negSeg) {
            let p = DSP.prominence(negSeg, i, seg.count)
            if p >= rel * rng {
                neg.append(i)
                pr.append(p)
            }
        }
        guard !neg.isEmpty else { return nil }
        var j = DSP.argmax(pr, 0, pr.count)
        if j > 0 && pr[j - 1] >= 0.9 * pr[j] { j -= 1 }
        let im = neg[j]
        let lim = im + Int(0.06 * fsHi)
        for p in DSP.localMax(seg) where p > im && p <= lim {
            if DSP.prominence(seg, p, seg.count) >= 4 * rel * rng { return p }
        }
        return nil
    }

    /// AO = most prominent positive peak that has a negative peak (IM) within 60 ms before it.
    static func maxposAO(_ seg: [Double], rel: Double = 0.2) -> Int? {
        guard seg.count >= 10, let mx = seg.max(), let mn = seg.min() else { return nil }
        let rng = mx - mn
        let pos = DSP.localMax(seg)
        guard !pos.isEmpty else { return nil }
        let neg = DSP.localMax(seg.map { -$0 })
        let nw = Int(0.06 * fsHi)
        var best: Int?
        var bp = 0.0
        for i in pos {
            let p = DSP.prominence(seg, i, seg.count)
            if p >= rel * rng && p > bp && neg.contains(where: { $0 < i && $0 >= i - nw }) {
                best = i
                bp = p
            }
        }
        return best
    }

    struct EnsembleInfo {
        var template: [Double]
        var S: [[Double]]
        var aoI: Int?
        var pre: Int
    }

    static func scgFirstAOs(s: [Double], env: [Double], hrS: Double, T: Double, th0: Double) -> [Double] {
        var Ts = 1 / hrS
        if !Ts.isFinite || abs(Ts - T) > 0.1 * T { Ts = T }
        guard Ts.isFinite, Ts > 0 else { return [] }
        let ep = DSP.findPeaks(env, distance: Int(0.6 * Ts * fsHi), wl: Int(1.5 * Ts * fsHi), minRelProm: 0.3)
        let w = Int(0.08 * fsHi)
        var out: [Double] = []
        for e in ep {
            let a = max(0, e - w), b = min(s.count, e + w)
            if b > a { out.append(th0 + Double(DSP.argmax(s, a, b)) / fsHi) }
        }
        return out
    }

    static func detectAO(method: String, s: [Double], th0: Double, ft: [Double], okPre: [Bool],
                         scgFirst: [Double]) -> (ao: [Double], ens: EnsembleInfo?) {
        let n = ft.count
        var ao = [Double](repeating: .nan, count: n)
        let fs = fsHi
        switch method {
        case "rule":
            for k in 0..<n where ft[k].isFinite {
                let a = Int(((ft[k] - pttHi - th0) * fs).rounded())
                let b = Int(((ft[k] - pttLo - th0) * fs).rounded())
                if a < 0 || b >= s.count || b <= a { continue }
                if let r = ruleAO(Array(s[a..<b])) { ao[k] = th0 + Double(a + r) / fs }
            }
            return (ao, nil)
        case "ensemble":
            let pre = Int(0.5 * fs), post = Int(0.1 * fs)
            var segs: [[Double]] = []
            var idx: [Int] = []
            for k in 0..<n where ft[k].isFinite && okPre[k] {
                let c = Int(((ft[k] - th0) * fs).rounded())
                if c - pre < 0 || c + post >= s.count { continue }
                segs.append(Array(s[(c - pre)..<(c + post)]))
                idx.append(k)
            }
            guard segs.count >= 5 else { return (ao, nil) }
            let tmpl = DSP.columnMedian(segs)
            let a = pre - Int(pttHi * fs), b = pre - Int(pttLo * fs)
            guard a >= 0, b <= tmpl.count, b > a, let r = maxposAO(Array(tmpl[a..<b])) else {
                return (ao, EnsembleInfo(template: tmpl, S: segs, aoI: nil, pre: pre))
            }
            let aoI = a + r
            let w = Int(0.08 * fs), lagMax = Int(0.04 * fs)
            guard aoI - w >= 0, aoI + w <= tmpl.count else {
                return (ao, EnsembleInfo(template: tmpl, S: segs, aoI: aoI, pre: pre))
            }
            let ref = Array(tmpl[(aoI - w)..<(aoI + w)])
            let rm = DSP.mean(ref)
            let refc = ref.map { $0 - rm }
            let sn = Int(0.01 * fs)
            for (row, k) in Swift.zip(segs, idx) {
                var best = -Double.infinity
                var bl = 0
                for lag in -lagMax...lagMax {
                    let st = aoI - w + lag, en = aoI + w + lag
                    if st < 0 || en > row.count { continue }
                    var sm = 0.0
                    for q in st..<en { sm += row[q] }
                    let mu = sm / Double(en - st)
                    var cval = 0.0
                    for q in 0..<(en - st) { cval += (row[st + q] - mu) * refc[q] }
                    if cval > best {
                        best = cval
                        bl = lag
                    }
                }
                let j0 = aoI + bl
                let lo = max(0, j0 - sn), hi = min(row.count, j0 + sn + 1)
                let j = hi > lo ? DSP.argmax(row, lo, hi) : j0
                ao[k] = ft[k] + Double(j - pre) / fs
            }
            return (ao, EnsembleInfo(template: tmpl, S: segs, aoI: aoI, pre: pre))
        default:   // scg_first
            for k in 0..<n where ft[k].isFinite {
                var cand: [Double] = []
                for a in scgFirst {
                    let d = ft[k] - a
                    if d >= pttLo && d <= pttHi { cand.append(d) }
                }
                if cand.count == 1 {
                    ao[k] = ft[k] - cand[0]
                } else if cand.count > 1 {
                    let md = DSP.median(cand)
                    var pick = cand[0]
                    for c in cand where abs(c - md) < abs(pick - md) { pick = c }
                    ao[k] = ft[k] - pick
                }
            }
            return (ao, nil)
        }
    }

    // MARK: tap sync test

    static func events(_ x: [Double], _ tt: [Double], k: Double = 8) -> [Double] {
        let med = DSP.median(x)
        let mad = DSP.median(x.map { abs($0 - med) })
        let thr = med + k * 1.4826 * mad
        var ev: [Double] = []
        for i in 0..<min(x.count, tt.count) where x[i] > thr {
            if let l = ev.last, tt[i] - l <= 0.3 { continue }
            ev.append(tt[i])
        }
        return ev
    }

    /// Accelerometer tap onsets. Jolts closer than 0.3 s belong to one burst; bursts closer than 0.5 s
    /// (lift-off jolt + landing jolt, or a bounce) are merged, keeping the stronger one, timed at its onset.
    static func accTapEvents(_ x: [Double], _ tt: [Double], k: Double = 7) -> [Double] {
        let med = DSP.median(x)
        let mad = DSP.median(x.map { abs($0 - med) })
        let thr = med + k * 1.4826 * mad
        var subs: [(onset: Int, peak: Double, last: Int)] = []
        for i in 0..<min(x.count, tt.count) where x[i] > thr {
            if let l = subs.last, tt[i] - tt[l.last] <= 0.3 {
                subs[subs.count - 1].last = i
                subs[subs.count - 1].peak = max(l.peak, x[i])
            } else {
                subs.append((i, x[i], i))
            }
        }
        var out: [(onset: Int, peak: Double, last: Int)] = []
        for sb in subs {
            if let l = out.last, tt[sb.onset] - tt[l.onset] <= 0.5 {
                if sb.peak > l.peak { out[out.count - 1] = sb }
            } else {
                out.append(sb)
            }
        }
        return out.map { tt[$0.onset] }
    }

    /// Tap sync. Accelerometer taps are found first; then, within 0.25 s of each, the camera frame-to-frame
    /// light change (unfiltered, so no ringing) is searched for a jump clearly bigger than a heartbeat.
    /// Camera events are only counted next to accelerometer taps, so heartbeats can't be mistaken for taps.
    static func tapSync(at: [Double], ac: [String: [Double]], fsA: Double, P: PPG, t0: Double, t1: Double) -> (TapResult, PlotData) {
        let xs = ["x", "y", "z"].map { DSP.uniform(at, ac[$0] ?? [], fs: fsA, t0: t0, t1: t1).x }
        let n = xs.map { $0.count }.min() ?? 0
        var mag = [Double](repeating: 0, count: n)
        for i in 0..<n { mag[i] = sqrt(xs[0][i] * xs[0][i] + xs[1][i] * xs[1][i] + xs[2][i] * xs[2][i]) }
        let hp = DSP.bandpass(mag, fs: fsA, lo: 5, hi: 0.45 * fsA).map { abs($0) }
        var ta = [Double](repeating: 0, count: hp.count)
        for i in 0..<hp.count { ta[i] = t0 + Double(i) / fsA }
        let ea = accTapEvents(hp, ta)

        // camera: |frame-to-frame light change|, 2-frame average
        let L = P.rawL, rt = P.rawT
        var dL: [Double] = []
        var tt: [Double] = []
        if L.count > 2 && rt.count == L.count {
            var prev = 0.0
            for i in 0..<(L.count - 1) {
                let d = L[i + 1] - L[i]
                dL.append(abs(0.5 * (d + (i > 0 ? prev : 0))))
                tt.append(rt[i + 1])
                prev = d
            }
        }
        var thr = Double.infinity
        if !dL.isEmpty && P.hrHz.isFinite && P.hrHz > 0 && P.fs > 0 {
            let T = 1 / P.hrHz
            let pk = DSP.findPeaks(dL, distance: Int(0.6 * T * P.fs), wl: Int(1.5 * T * P.fs), minRelProm: 0)
            let hb = pk.isEmpty ? DSP.median(dL) : DSP.median(pk.map { dL[$0] })
            thr = 2.5 * hb
        }
        var off: [Double] = []
        var camTimes: [Double] = []
        for e in ea {
            var best = -1
            var bd = Double.infinity
            var j = 1
            while j < dL.count - 1 {
                let dt = tt[j] - e
                if dt > 0.25 { break }
                if dt >= -0.25 && dL[j] >= thr && dL[j] >= dL[j - 1] && dL[j] >= dL[j + 1] && abs(dt) < bd {
                    bd = abs(dt)
                    best = j
                }
                j += 1
            }
            if best >= 0 {
                off.append(tt[best] - e)
                camTimes.append(tt[best])
            }
        }
        var r = TapResult()
        r.accTaps = ea.count
        r.ppgEvents = off.count
        r.paired = off.count
        r.offsetMedianMs = off.isEmpty ? .nan : 1000 * DSP.median(off)
        r.offsetSdMs = off.count > 1 ? 1000 * DSP.std(off) : .nan
        var pd = PlotData()
        pd.isTap = true
        pd.label = "Tap sync"
        pd.x0 = 0
        pd.x1 = t1 - t0
        pd.light = dL
        pd.lightStart = (tt.first ?? t0) - t0
        pd.lightDt = P.fs > 0 ? 1 / P.fs : 0.01
        pd.scg = hp
        pd.start = 0
        pd.dt = 1 / fsA
        pd.featureTimes = camTimes.map { $0 - t0 }
        pd.aoTimes = ea.map { $0 - t0 }
        pd.aoValid = [Bool](repeating: true, count: ea.count)
        return (r, pd)
    }

    // MARK: one session

    static func analyze(folder: URL) throws -> AnalysisResult {
        let d = try load(folder)
        var R = AnalysisResult()
        R.session = d.name
        R.mode = d.mode
        R.lens = d.lens
        R.torchPct = d.torchPct
        R.device = d.device.isEmpty ? "" : "\(d.device), iOS \(d.os)"
        R.created = ISO8601DateFormatter().string(from: Date())
        let ptAll = d.ppg["t"] ?? [], atAll = d.acc["t"] ?? []
        R.rates = [rateReport(ptAll, "camera"), rateReport(atAll, "accelerometer")]

        var pc: [String: [Double]] = [:]
        for (k, v) in d.ppg { pc[k] = pickRows(v, d.ppgRecord) }
        var ac: [String: [Double]] = [:]
        for (k, v) in d.acc { ac[k] = pickRows(v, d.accRecord) }
        let pt = pc["t"] ?? [], at = ac["t"] ?? []
        guard pt.count > 50, at.count > 50, let pmin = pt.min(), let pmax = pt.max(),
              let amin = at.min(), let amax = at.max() else { throw AnalysisError.tooShort(0) }
        let t0 = max(pmin, amin) + edgeTrim
        let t1 = min(pmax, amax) - edgeTrim
        R.spanS = t1 - t0
        guard t1 - t0 >= 10 else { throw AnalysisError.tooShort(max(0, t1 - t0)) }
        let fsP = DSP.rate(pt), fsA = DSP.rate(at)
        guard fsP >= 10 else { throw AnalysisError.badRate("camera") }
        guard fsA >= 20 else { throw AnalysisError.badRate("accelerometer") }

        if let iso = pc["iso"], let e = pc["exp_ms"] {
            R.isoRange = [iso.min() ?? .nan, iso.max() ?? .nan]
            R.expRange = [e.min() ?? .nan, e.max() ?? .nan]
            R.exposureFixed = (R.isoRange[1] - R.isoRange[0]) < 1 && (R.expRange[1] - R.expRange[0]) < 0.01
            if !R.exposureFixed { R.warnings.append("Camera exposure changed during the recording, so light levels are not comparable over time.") }
        }

        // finger colour: the saved one if there is one; otherwise the best that passes every check
        let quals = assessColours(t: pt, cols: pc, fs: fsP, t0: t0, t1: t1)
        R.channelQuality = quals
        R.colourSetup = d.colourSetup
        R.flashRaised = d.flashRaised
        var flags = d.flags
        var force: String?
        if let lk = d.lockedChannel, pc[lk] != nil {
            force = lk
            R.channelSource = "locked"
        } else if let b = bestColour(quals) {
            force = b
            R.channelSource = "auto"
        } else {
            R.channelSource = "fallback"
        }
        let P = ppgProcess(t: pt, cols: pc, fs: fsP, t0: t0, t1: t1, force: force)
        let usedQ = quals.first { $0.channel == P.channel }
        R.channelPassed = usedQ?.passed ?? false
        if d.mode != "tap" {
            if R.channelSource == "locked", let q = usedQ, !q.passed {
                flags.append("The saved finger colour (\(ColourProfile.name(q.channel))) failed the quality check: \(q.reason).")
            } else if R.channelSource == "fallback" {
                let why = usedQ?.reason ?? "no clean pulse"
                flags.append("The finger pulse failed the quality check in every colour (\(ColourProfile.name(P.channel)): \(why)). Results are unreliable.")
            }
        }
        R.flags = flags.isEmpty ? nil : flags
        R.channels = P.info
        R.channel = P.channel
        R.hrPpg = 60 * P.hrHz
        let brightest = P.info.map { $0.mean }.max() ?? 0
        // light drift: brightest channel, median of the first vs last 5 s (flash warming, finger pressure)
        if let bc = P.info.max(by: { $0.mean < $1.mean }), let col = pc[bc.channel] {
            let lb = DSP.uniform(pt, col, fs: fsP, t0: t0, t1: t1).x
            let w = min(Int(5 * fsP), lb.count / 3)
            if w > 10 {
                let first = DSP.median(Array(lb[0..<w]))
                let last = DSP.median(Array(lb[(lb.count - w)..<lb.count]))
                if first > 1 {
                    let drift = 100 * (last - first) / first
                    R.lightDriftPct = drift
                    if abs(drift) > 5 && d.mode != "tap" {
                        R.warnings.append(String(format: "Finger light changed by %+.1f%% during the recording (flash warming up, or finger pressure changing). Pulse size and PIR may drift with it.", drift))
                    }
                }
            }
        }
        if brightest < 60 {
            R.warnings.append(String(format: "Finger signal very dark (brightest colour %.0f of 255; aim for 150 to 235). The flash light is not reaching the camera: cover the lens and the flash with one fingertip, or choose a lens closer to the flash.", brightest))
        }

        if d.mode == "tap" {
            let ts = tapSync(at: at, ac: ac, fsA: fsA, P: P, t0: t0, t1: t1)
            R.tap = ts.0
            R.plot = ts.1
            if let tp = R.tap {
                if tp.accTaps < 4 {
                    R.warnings.append("Fewer than 4 taps found in the accelerometer. Tap more firmly, about every 4 seconds.")
                } else if tp.paired < 4 {
                    R.warnings.append("The accelerometer felt the taps but the camera barely saw them. Lift the camera fingertip about 1 cm and tap it straight back down onto the camera.")
                }
            }
            R.text = report(R)
            try save(R, folder)
            return R
        }

        let B = ppgBeats(P)
        R.nBeats = B.count
        R.nPpgOk = B.filter { $0.ok }.count
        guard B.count >= 5 else {
            R.warnings.append("Too few finger-pulse beats detected. Check finger contact, the flash and saturation.")
            R.text = report(R)
            try save(R, folder)
            return R
        }
        let pirOk = B.filter { $0.ok && $0.pir.isFinite }.map { $0.pir }
        R.pirMedian = DSP.median(pirOk)
        R.pirCv = 100 * DSP.robustSD(pirOk) / R.pirMedian

        let S = scgAxes(t: at, cols: ac, fs: fsA, t0: t0, t1: t1)
        R.gravity = S.grav
        let n = min(S.sig.values.map { $0.count }.min() ?? 0, P.t.count)
        let th0 = t0
        let T = 1 / P.hrHz
        var combos: [Combo] = []
        var store: [String: (ao: [Double], valid: [Bool])] = [:]
        var ensStore: [String: EnsembleInfo] = [:]
        var sigs: [String: [Double]] = [:]
        let okPPG = B.map { $0.ok }

        for band in S.bands {
            for axis in ["dv", "pca"] {
                guard let full = S.sig[band + "|" + axis] else { continue }
                let s = Array(full.prefix(n))
                sigs[band + "|" + axis] = s
                let hrInfo = scgHR(s)
                var rms: [Double] = []
                for b in B {
                    let c = Int(((b.tPeak - th0) * fsHi).rounded())
                    let a = max(0, c - 500), e = min(s.count, c + 100)
                    if e > a {
                        var q = 0.0
                        for i in a..<e { q += s[i] * s[i] }
                        rms.append(sqrt(q / Double(e - a)))
                    } else {
                        rms.append(.nan)
                    }
                }
                let medR = DSP.median(rms)
                var okPre = [Bool](repeating: false, count: B.count)
                for k in 0..<B.count { okPre[k] = okPPG[k] && rms[k] < 2.5 * medR }
                let sf = scgFirstAOs(s: s, env: hrInfo.env, hrS: hrInfo.hrHz, T: T, th0: th0)
                for feat in features {
                    let ft = B.map { $0.time(feat) }
                    for meth in methods {
                        let res = detectAO(method: meth, s: s, th0: th0, ft: ft, okPre: okPre, scgFirst: sf)
                        var valid = [Bool](repeating: false, count: B.count)
                        var pv: [Double] = []
                        for k in 0..<B.count {
                            let p = ft[k] - res.ao[k]
                            if okPre[k] && p.isFinite && p >= pttLo && p <= pttHi {
                                valid[k] = true
                                pv.append(p * 1000)
                            }
                        }
                        let half = pv.count / 2
                        var c = Combo()
                        c.method = meth
                        c.band = band
                        c.axis = axis
                        c.feature = feat
                        c.beats = B.count
                        c.valid = pv.count
                        c.yieldPct = 100 * Double(pv.count) / Double(B.count)
                        c.hrScg = 60 * hrInfo.hrHz
                        c.pttMedianMs = DSP.median(pv)
                        c.pttIqrMs = pv.count > 3 ? DSP.percentile(pv, 75) - DSP.percentile(pv, 25) : .nan
                        c.pttRobustSdMs = DSP.robustSD(pv)
                        c.splitHalfMs = half >= 5 ? DSP.median(Array(pv[..<half])) - DSP.median(Array(pv[half...])) : .nan
                        combos.append(c)
                        store[c.key] = (res.ao, valid)
                        if let e = res.ens { ensStore[c.key] = e }
                    }
                }
            }
        }

        // heartbeat check: only 60-400 ms before the finger pulse (where the AO is searched).
        // Decisions use the out-of-chest axis (dv = -z); the best-direction axis is extra information.
        let okT = B.filter { $0.ok && $0.tangentFoot.isFinite }.map { $0.tangentFoot }
        for band in S.bands.sorted() {
            for axis in ["dv", "pca"] {
                guard let s = sigs[band + "|" + axis] else { continue }
                let lk = DSP.beatLock(s, th0: th0, fs: fsHi, times: okT, winS: (-pttHi, -pttLo))
                let la = DSP.beatLock(s, th0: th0, fs: fsHi, times: okT)
                var entry = BandLock(band: band, ratio: lk.ratio, snrDb: lk.snrDb, verdict: lockVerdict(lk.ratio))
                entry.axis = axis
                entry.ratioAll = la.ratio
                R.locks.append(entry)
            }
        }
        let used = R.bestLock
        R.scgDetected = used > 3
        if d.mode == "table" {
            if used > 3 {
                R.warnings.append("The finger pulse leaks into the out-of-chest direction, in the window where the chest analysis looks for the heartbeat. Chest PTT could be contaminated: try lighter finger pressure.")
            } else if R.anyLock > 3 {
                R.notes = ["A small finger-pulse movement shows in another direction or just after the pulse. It falls outside what the chest analysis uses, so chest results are not affected."]
            } else {
                R.notes = ["No finger-pulse movement found in any direction."]
            }
        } else if !(used > 3) {
            R.warnings.append("No heartbeat locked to the finger pulse in the out-of-chest chest signal. The averaged method still returns numbers from pure noise, so treat every PTT in this session as INVALID.")
        }

        R.hrScg = DSP.median(combos.map { $0.hrScg })
        let good = combos.filter { $0.valid >= minValidBeats && $0.yieldPct >= 50 }
            .sorted { ($0.pttRobustSdMs.isFinite ? $0.pttRobustSdMs : .infinity) < ($1.pttRobustSdMs.isFinite ? $1.pttRobustSdMs : .infinity) }
        R.ranked = Array(good.prefix(10))
        let fixedKey = "\(fixedMethod)|\(S.bands.first ?? "")|\(fixedAxis)|\(fixedFeature)"
        R.fixed = combos.first { $0.key == fixedKey }

        var plotKey: String?
        if let st = store[fixedKey], st.valid.contains(true) {
            plotKey = fixedKey
        } else {
            plotKey = good.first?.key
        }
        if let key = plotKey, let st = store[key], let combo = combos.first(where: { $0.key == key }),
           let s = sigs[combo.band + "|" + combo.axis] {
            let ens = ensStore["ensemble|\(combo.band)|\(combo.axis)|\(combo.feature)"]
            R.plot = makePlot(P: P, B: B, s: s, th0: th0, combo: combo, ao: st.ao, valid: st.valid, ens: ens,
                              markers: d.markers, isFixed: key == fixedKey)
        }
        R.text = report(R)
        try save(R, folder)
        return R
    }

    static func makePlot(P: PPG, B: [Beat], s: [Double], th0: Double, combo: Combo, ao: [Double], valid: [Bool],
                         ens: EnsembleInfo?, markers: [Double], isFixed: Bool) -> PlotData {
        var pd = PlotData()
        let span = Double(P.v.count) / fsHi
        let x0 = span >= 15 ? 5.0 : 0.0
        let x1 = min(span, x0 + 10)
        pd.x0 = x0
        pd.x1 = x1
        pd.featureName = featureName(combo.feature)
        pd.label = (isFixed ? "Fixed method: " : "Most stable combination: ")
            + "\(methodName(combo.method)), \(combo.band), \(combo.axis == "pca" ? "best-direction axis" : "out-of-chest axis (-z)"), \(featureName(combo.feature))"
        // raw light, native rate
        if P.fs > 0 {
            let ia = Int((x0 * P.fs).rounded(.up)), ib = min(P.rawL.count, Int(x1 * P.fs))
            if ib > ia {
                pd.light = Array(P.rawL[ia..<ib])
                pd.lightStart = Double(ia) / P.fs
                pd.lightDt = 1 / P.fs
            }
        }
        let a = Int(x0 * fsHi), b = min(min(P.v.count, s.count), Int(x1 * fsHi))
        let step = 5
        if b > a {
            var i = a
            while i < b {
                pd.ppg.append(P.v[i])
                pd.scg.append(s[i])
                i += step
            }
        }
        pd.start = Double(a) / fsHi
        pd.dt = Double(step) / fsHi
        for bt in B {
            let x = bt.time(combo.feature) - th0
            if x.isFinite && x >= x0 && x <= x1 { pd.featureTimes.append(x) }
        }
        for (k, v) in ao.enumerated() where v.isFinite {
            let x = v - th0
            if x >= x0 && x <= x1 {
                pd.aoTimes.append(x)
                pd.aoValid.append(k < valid.count ? valid[k] : false)
            }
        }
        for m in markers where m.isFinite {
            let x = m - th0
            if x >= x0 && x <= x1 { pd.markerTimes.append(x) }
        }
        if let e = ens {
            let q1 = DSP.columnPercentile(e.S, 25), q3 = DSP.columnPercentile(e.S, 75)
            var i = 0
            while i < e.template.count {
                pd.tmpl.append(e.template[i])
                pd.q1.append(i < q1.count ? q1[i] : .nan)
                pd.q3.append(i < q3.count ? q3[i] : .nan)
                i += 2
            }
            pd.tmplStartMs = -Double(e.pre) / fsHi * 1000
            pd.tmplDtMs = 2 / fsHi * 1000
            if let ai = e.aoI { pd.aoMs = Double(ai - e.pre) / fsHi * 1000 }
        }
        for k in 0..<B.count {
            if k < valid.count && valid[k] && k < ao.count {
                pd.ptt.append(SeriesPoint(x: B[k].tPeak - th0, y: (B[k].time(combo.feature) - ao[k]) * 1000))
            }
            if B[k].ok && B[k].pir.isFinite { pd.pir.append(SeriesPoint(x: B[k].tPeak - th0, y: B[k].pir)) }
        }
        return pd
    }

    // MARK: text report (also saved as analysis/summary.txt)

    static func f1(_ v: Double) -> String { v.isFinite ? String(format: "%.1f", v) : "nan" }

    static func report(_ R: AnalysisResult) -> String {
        var L: [String] = []
        L.append("Session: \(R.session)")
        L.append("Mode: \(R.mode)   Device: \(R.device)   Lens: \(R.lens ?? "main")   Flash: \(R.torchPct.map { String(format: "%.0f%%", $0) } ?? "100%")")
        L.append("Analysed span: \(f1(R.spanS)) s   (analysed on the phone, HC Capture 0.3.3)")
        L.append("")
        L.append("Capture quality")
        for r in R.rates {
            L.append("  \(r.name.padding(toLength: 13, withPad: " ", startingAt: 0)) \(f1(r.rateHz)) Hz  jitter \(String(format: "%.2f", r.jitterMs)) ms  gaps \(r.gaps)  longest \(f1(r.longestGapMs)) ms")
        }
        if R.isoRange.count == 2 && R.expRange.count == 2 {
            if let dr = R.lightDriftPct { L.append("  finger light drift first-to-last 5 s: \(String(format: "%+.1f", dr))%") }
            L.append("  camera ISO \(String(format: "%.0f-%.0f", R.isoRange[0], R.isoRange[1])), exposure \(String(format: "%.2f-%.2f", R.expRange[0], R.expRange[1])) ms during record (should be constant)")
        }
        L.append("")
        L.append("PPG channels (mean 0-255, pulsatility = AC/DC, peak ratio = heartbeat clarity)")
        for c in R.channels {
            L.append("  \(c.channel): mean \(f1(c.mean))  pulsatility \(String(format: "%.2f", c.pulsatilityPct))%  peak ratio \(f1(c.peakRatio))" + (c.channel == R.channel ? "   <- used" : ""))
        }
        L.append("  PPG heart rate \(f1(R.hrPpg)) bpm")
        if let qs = R.channelQuality {
            let src: String
            switch R.channelSource {
            case "locked": src = "saved colour"
            case "auto": src = "chosen now: passed every check, most consistent beats"
            default: src = "none passed; best available used"
            }
            L.append("  Colour used: \(ColourProfile.name(R.channel)) (\(src))")
            L.append("  Quality per colour (clean beats, rhythm clarity, timing variation, beat shape, match with other colour):")
            for q in qs {
                let ag = q.agreementPct.map { String(format: "%.0f%%", $0) } ?? "not checked"
                let verdict = q.passed ? "pass" : "fail: \(q.reason)"
                L.append("    \(q.channel): \(q.okBeats)/\(q.beats), clarity \(f1(q.peakRatio)), timing \(f1(q.ibiCvPct))%, shape \(String(format: "%.3f", q.shapeCorr)), match \(ag) -> \(verdict)")
            }
        }
        if let t = R.tap {
            L.append("")
            L.append("Tap sync test")
            L.append("  taps in accelerometer \(t.accTaps), seen by the camera \(t.paired)")
            L.append("  PPG minus accelerometer offset: median \(f1(t.offsetMedianMs)) ms, SD \(f1(t.offsetSdMs)) ms")
            L.append("  (includes finger mechanics; a stable value across repeats matters more than zero)")
        } else {
            L.append("  beats \(R.nBeats), passing PPG quality \(R.nPpgOk)")
            if R.pirMedian.isFinite {
                L.append("  PIR median \(String(format: "%.4f", R.pirMedian)), robust CV \(String(format: "%.2f", R.pirCv))%")
            }
            if R.gravity.count == 3 {
                L.append("")
                L.append("SCG  gravity (g): x \(String(format: "%+.2f", R.gravity[0])) y \(String(format: "%+.2f", R.gravity[1])) z \(String(format: "%+.2f", R.gravity[2]))")
            }
            if !R.locks.isEmpty {
                L.append("  Heartbeat check (beat-locked ratio: >6 clear, 3-6 weak, <3 none)")
                L.append("    'before pulse' = only 60-400 ms before the finger pulse, where the AO is searched;")
                L.append("    the out-of-chest axis before the pulse is what decisions use")
            }
            for lk in R.locks {
                var line = "  SCG \(lk.band) \(axisName(lk.axis)): before pulse \(f1(lk.ratio)) (\(lk.verdict))"
                if let a = lk.ratioAll { line += ", whole window \(f1(a)) (\(lockVerdict(a)))" }
                L.append(line)
            }
            if let fx = R.fixed {
                L.append("")
                L.append("Fixed method (use this to compare sessions): \(methodName(fx.method)), \(fx.band), \(axisName(fx.axis)) axis, \(featureName(fx.feature))")
                L.append("  PTT median \(f1(fx.pttMedianMs)) ms, robust SD \(f1(fx.pttRobustSdMs)) ms, IQR \(f1(fx.pttIqrMs)) ms, valid \(fx.valid)/\(fx.beats) beats, split-half \(f1(fx.splitHalfMs)) ms")
            }
            if !R.locks.isEmpty {
                L.append("")
                L.append("PTT combinations ranked by within-recording spread (lower = more stable)")
                L.append("  method     band       axis feature        valid  yield  median  robSD  split-half")
                if R.ranked.isEmpty {
                    L.append("  none passed (need >= \(minValidBeats) valid beats and >= 50% yield)")
                }
                for c in R.ranked {
                    L.append("  \(c.method.padding(toLength: 10, withPad: " ", startingAt: 0)) \(c.band.padding(toLength: 10, withPad: " ", startingAt: 0)) \(c.axis.padding(toLength: 4, withPad: " ", startingAt: 0)) \(c.feature.padding(toLength: 14, withPad: " ", startingAt: 0)) \(String(format: "%5ld  %4.0f%%  %6.1f  %5.1f  %+6.1f", c.valid, c.yieldPct, c.pttMedianMs, c.pttRobustSdMs, c.splitHalfMs))")
                }
                L.append("")
                L.append("Caution: choosing the 'best' row from many combinations overfits. Use pilot sessions")
                L.append("to pick ONE combination, write it down, then judge it on new sessions only.")
            }
        }
        if let fl = R.flags, !fl.isEmpty {
            L.append("")
            for f in fl { L.append("FLAGGED: \(f)") }
        }
        if let ns = R.notes, !ns.isEmpty {
            L.append("")
            for nt in ns { L.append("Note: \(nt)") }
        }
        if !R.warnings.isEmpty {
            L.append("")
            for w in R.warnings { L.append("WARNING: \(w)") }
        }
        L.append("")
        L.append("RESEARCH PROTOTYPE. Not a medical device. These are signal-quality numbers, not blood pressure.")
        return L.joined(separator: "\n")
    }
}
