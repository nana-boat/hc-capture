import Foundation

/// Results of the slower live check (run once a second on the last 20 s).
struct LiveBeat {
    var hr = Double.nan          // bpm, from the finger pulse
    var avg: [Double] = []       // chest signal averaged around each finger-pulse foot
    var startMs = -500.0
    var dtMs = 10.0
    var lock = Double.nan        // beat-locked ratio (>6 clear, 3-6 weak, <3 none)
    var n = 0                    // beats used
    var channel = "g"
}

/// Light-weight filtering for the live screen. Uses the same filters as the full analysis.
enum LiveDSP {
    static func value(_ p: PPGSample, _ channel: String) -> Double {
        switch channel {
        case "r": return Double(p.r)
        case "b": return Double(p.b)
        default: return Double(p.g)
        }
    }

    static func tail(_ y: [Double], count: Int, maxPoints: Int) -> [Double] {
        guard !y.isEmpty, count > 0 else { return [] }
        let a = max(0, y.count - count)
        let part = Array(y[a..<y.count])
        let step = max(1, part.count / maxPoints)
        var out: [Double] = []
        var i = 0
        while i < part.count {
            out.append(part[i])
            i += step
        }
        return out
    }

    /// Finger pulse, band-passed 0.5-10 Hz and flipped so more blood = up. Last `show` seconds.
    static func ppgWave(_ s: [PPGSample], channel: String, show: Double, maxPoints: Int = 300) -> [Double] {
        guard s.count > 20, let t0 = s.first?.t, let t1 = s.last?.t else { return [] }
        let t = s.map { $0.t }
        let fs = DSP.rate(t)
        guard fs >= 10 else { return [] }
        let L = DSP.uniform(t, s.map { value($0, channel) }, fs: fs, t0: t0, t1: t1).x
        let y = DSP.bandpass(L, fs: fs, lo: 0.5, hi: 10).map { -$0 }
        return tail(y, count: Int(show * fs), maxPoints: maxPoints)
    }

    /// Chest accelerometer on the out-of-chest axis (-z), band-passed 5-40 Hz. Last `show` seconds.
    static func scgWave(_ s: [XYZSample], show: Double, maxPoints: Int = 400) -> [Double] {
        guard s.count > 20, let t0 = s.first?.t, let t1 = s.last?.t else { return [] }
        let t = s.map { $0.t }
        let fs = DSP.rate(t)
        guard fs >= 20 else { return [] }
        let z = DSP.uniform(t, s.map { $0.z }, fs: fs, t0: t0, t1: t1).x
        let y = DSP.bandpass(z, fs: fs, lo: 5, hi: 40).map { -$0 }
        return tail(y, count: Int(show * fs), maxPoints: maxPoints)
    }

    /// Heart rate, and the chest signal averaged around each finger-pulse foot (shows whether the
    /// heartbeat is reaching the accelerometer while you adjust the phone).
    static func beatSummary(ppg: [PPGSample], acc: [XYZSample]) -> LiveBeat {
        var out = LiveBeat()
        guard ppg.count > 50, acc.count > 50,
              let p0 = ppg.first?.t, let p1 = ppg.last?.t,
              let a0 = acc.first?.t, let a1 = acc.last?.t else { return out }
        let t0 = max(p0, a0) + 0.5
        let t1 = min(p1, a1)
        guard t1 - t0 > 6 else { return out }
        let tp = ppg.map { $0.t }
        let fsP = DSP.rate(tp)
        let ta = acc.map { $0.t }
        let fsA = DSP.rate(ta)
        guard fsP >= 10, fsA >= 20 else { return out }

        // pick the colour channel with the strongest pulse
        var bestCh = "g", bestScore = -1.0
        var bestL: [Double] = []
        for ch in ["g", "r"] {
            let L = DSP.uniform(tp, ppg.map { value($0, ch) }, fs: fsP, t0: t0, t1: t1).x
            let mu = DSP.mean(L)
            let ac = DSP.bandpass(L, fs: fsP, lo: 0.7, hi: 3.5)
            let sd = DSP.std(ac)
            let score = (mu > 5 && mu < 250 && sd.isFinite) ? sd / mu : 0
            if score > bestScore {
                bestScore = score
                bestCh = ch
                bestL = L
            }
        }
        out.channel = bestCh
        let v = DSP.bandpass(bestL, fs: fsP, lo: 0.5, hi: 10).map { -$0 }
        let hr = DSP.dominantHR(v, fs: fsP)
        guard hr.isFinite, hr > 0 else { return out }
        out.hr = 60 * hr
        let T = 1 / hr
        let pk = DSP.findPeaks(v, distance: Int(0.6 * T * fsP), wl: Int(1.5 * T * fsP), minRelProm: 0.3)
        var feet: [Double] = []
        for i in pk {
            let a = max(0, i - Int(0.5 * T * fsP))
            if i - a < 3 { continue }
            feet.append(t0 + Double(DSP.argmin(v, a, i)) / fsP)
        }
        let z = DSP.uniform(ta, acc.map { $0.z }, fs: fsA, t0: t0, t1: t1).x
        let s = DSP.bandpass(z, fs: fsA, lo: 5, hi: 40).map { -$0 }
        let lk = DSP.beatLock(s, th0: t0, fs: fsA, times: feet)
        out.lock = lk.ratio
        out.n = lk.count
        out.avg = lk.template
        out.startMs = -Double(Int(0.5 * fsA)) / fsA * 1000
        out.dtMs = 1000 / fsA
        return out
    }
}
