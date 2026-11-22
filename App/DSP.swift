import Foundation

/// Signal-processing helpers, ported from analysis/hc_analyze.py so the analysis runs on the phone.
/// Differences from the laptop script (checked on test signals, about 1% difference):
///  - FFTs are padded to a power of two (pads are tapered first).
///  - Upsampling to 1000 Hz uses Lanczos (windowed-sinc) interpolation of the filtered signal
///    instead of FFT zero-padding.
enum DSP {
    static func nextPow2(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    /// In-place iterative radix-2 complex FFT. Length must be a power of two.
    static func fft(_ re: inout [Double], _ im: inout [Double], inverse: Bool) {
        let n = re.count
        guard n > 1, im.count == n else { return }
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var len = 2
        while len <= n {
            let ang = 2 * Double.pi / Double(len) * (inverse ? 1 : -1)
            let wr = cos(ang), wi = sin(ang)
            let half = len / 2
            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0
                for k in 0..<half {
                    let a = i + k, b = i + k + half
                    let tr = re[b] * cr - im[b] * ci
                    let ti = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                    let ncr = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = ncr
                }
                i += len
            }
            len <<= 1
        }
        if inverse {
            let s = 1.0 / Double(n)
            for i in 0..<n {
                re[i] *= s
                im[i] *= s
            }
        }
    }

    // MARK: basic statistics (NaN values are ignored)

    static func finite(_ x: [Double]) -> [Double] { x.filter { $0.isFinite } }

    static func mean(_ x: [Double]) -> Double {
        let v = finite(x)
        return v.isEmpty ? .nan : v.reduce(0, +) / Double(v.count)
    }

    /// Population SD, like numpy.std.
    static func std(_ x: [Double]) -> Double {
        let v = finite(x)
        guard !v.isEmpty else { return .nan }
        let m = v.reduce(0, +) / Double(v.count)
        var s = 0.0
        for e in v { s += (e - m) * (e - m) }
        return sqrt(s / Double(v.count))
    }

    /// Sample SD (n - 1).
    static func sampleSD(_ x: [Double]) -> Double {
        let v = finite(x)
        guard v.count > 1 else { return .nan }
        let m = v.reduce(0, +) / Double(v.count)
        var s = 0.0
        for e in v { s += (e - m) * (e - m) }
        return sqrt(s / Double(v.count - 1))
    }

    static func median(_ x: [Double]) -> Double { percentile(x, 50) }

    /// Linear-interpolated percentile, like numpy.percentile.
    static func percentile(_ x: [Double], _ q: Double) -> Double {
        let v = finite(x).sorted()
        guard !v.isEmpty else { return .nan }
        let pos = q / 100 * Double(v.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(lo + 1, v.count - 1)
        return v[lo] + (v[hi] - v[lo]) * (pos - Double(lo))
    }

    static func robustSD(_ x: [Double]) -> Double {
        let v = finite(x)
        guard !v.isEmpty else { return .nan }
        let m = median(v)
        return 1.4826 * median(v.map { abs($0 - m) })
    }

    static func diff(_ x: [Double]) -> [Double] {
        guard x.count > 1 else { return [] }
        var d = [Double](repeating: 0, count: x.count - 1)
        for i in 1..<x.count { d[i - 1] = x[i] - x[i - 1] }
        return d
    }

    /// Sampling rate rounded to a whole number of Hz, or 0 if it cannot be worked out.
    static func rate(_ t: [Double]) -> Double {
        let md = median(diff(t))
        guard md.isFinite, md > 0 else { return 0 }
        let r = (1 / md).rounded()
        return r.isFinite ? r : 0
    }

    /// Index of the maximum in [a, b) (first one on ties). Returns a if the range is empty.
    static func argmax(_ x: [Double], _ a: Int, _ b: Int) -> Int {
        var bi = a
        var bv = -Double.infinity
        var i = max(0, a)
        let e = min(b, x.count)
        while i < e {
            if x[i] > bv {
                bv = x[i]
                bi = i
            }
            i += 1
        }
        return bi
    }

    static func argmin(_ x: [Double], _ a: Int, _ b: Int) -> Int {
        var bi = a
        var bv = Double.infinity
        var i = max(0, a)
        let e = min(b, x.count)
        while i < e {
            if x[i] < bv {
                bv = x[i]
                bi = i
            }
            i += 1
        }
        return bi
    }

    /// numpy.gradient times the sampling rate.
    static func gradient(_ x: [Double], fs: Double) -> [Double] {
        let n = x.count
        guard n > 1 else { return [Double](repeating: 0, count: n) }
        var g = [Double](repeating: 0, count: n)
        g[0] = (x[1] - x[0]) * fs
        g[n - 1] = (x[n - 1] - x[n - 2]) * fs
        if n > 2 {
            for i in 1..<(n - 1) { g[i] = 0.5 * (x[i + 1] - x[i - 1]) * fs }
        }
        return g
    }

    /// numpy.interp: xq and xp ascending.
    static func interp(_ xq: [Double], _ xp: [Double], _ fp: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: xq.count)
        let m = min(xp.count, fp.count)
        guard m > 0 else { return out }
        let first = xp[0], last = xp[m - 1]
        var j = 0
        for (i, x) in xq.enumerated() {
            if x <= first { out[i] = fp[0]; continue }
            if x >= last { out[i] = fp[m - 1]; continue }
            while j < m - 2 && xp[j + 1] < x { j += 1 }
            let x0 = xp[j], x1 = xp[j + 1]
            out[i] = x1 > x0 ? fp[j] + (fp[j + 1] - fp[j]) * (x - x0) / (x1 - x0) : fp[j]
        }
        return out
    }

    /// Linear resample of irregular samples onto a uniform grid [t0, t1).
    static func uniform(_ t: [Double], _ x: [Double], fs: Double, t0: Double, t1: Double) -> (t: [Double], x: [Double]) {
        guard fs > 0, t1 > t0 else { return ([], []) }
        let n = Int(((t1 - t0) * fs).rounded(.down))
        var tg = [Double](repeating: 0, count: n)
        for i in 0..<n { tg[i] = t0 + Double(i) / fs }
        return (tg, interp(tg, t, x))
    }

    static func lineFit(_ x: [Double]) -> (a: Double, b: Double) {
        guard x.count > 1 else { return (0, x.first ?? 0) }
        let n = Double(x.count)
        var st = 0.0, sx = 0.0, stt = 0.0, stx = 0.0
        for (i, v) in x.enumerated() {
            let t = Double(i)
            st += t; sx += v; stt += t * t; stx += t * v
        }
        let den = n * stt - st * st
        let a = den != 0 ? (n * stx - st * sx) / den : 0
        return (a, (sx - a * st) / n)
    }

    /// Filter gain, same shape as _mask() in hc_analyze.py.
    static func gain(_ f: Double, fs: Double, lo: Double, hi: Double?) -> Double {
        var m = 1.0
        if lo > 0 {
            let w = max(0.25 * lo, 0.15)
            if f <= lo - w {
                m = 0
            } else if f < lo {
                m = 0.5 - 0.5 * cos(Double.pi * (f - (lo - w)) / w)
            }
        }
        if let h0 = hi {
            let h = min(h0, 0.45 * fs)
            let w = max(0.15 * h, 0.5)
            if f >= h + w {
                m = 0
            } else if f > h {
                m *= 0.5 + 0.5 * cos(Double.pi * (f - h) / w)
            }
        }
        return m
    }

    /// Zero-phase FFT band-pass (lo = 0 keeps DC and trend). Same length and rate as the input.
    static func bandpass(_ x: [Double], fs: Double, lo: Double, hi: Double?, padS: Double = 2.0) -> [Double] {
        let n0 = x.count
        guard n0 > 8, fs > 0 else { return x }
        let p = min(Int(padS * fs), n0 - 1)
        var xp = [Double]()
        xp.reserveCapacity(n0 + 2 * p)
        if p > 0 { for i in stride(from: p, through: 1, by: -1) { xp.append(x[i]) } }
        xp.append(contentsOf: x)
        if p > 0 { for k in 0..<p { xp.append(x[n0 - 2 - k]) } }
        let fit = lineFit(xp)
        for i in 0..<xp.count { xp[i] -= fit.a * Double(i) + fit.b }
        if p > 0 {
            let last = xp.count - 1
            for i in 0..<p {
                let w = 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(p))
                xp[i] *= w
                xp[last - i] *= w
            }
        }
        let nn = nextPow2(xp.count)
        var re = xp
        re.append(contentsOf: [Double](repeating: 0, count: nn - xp.count))
        var im = [Double](repeating: 0, count: nn)
        fft(&re, &im, inverse: false)
        let half = nn / 2
        for k in 0...half {
            let g = gain(Double(k) * fs / Double(nn), fs: fs, lo: lo, hi: hi)
            re[k] *= g
            im[k] *= g
            if k > 0 && k < half {
                re[nn - k] *= g
                im[nn - k] *= g
            }
        }
        fft(&re, &im, inverse: true)
        var y = Array(re[p..<(p + n0)])
        if lo <= 0 {
            for i in 0..<n0 { y[i] += fit.a * Double(i + p) + fit.b }
        }
        return y
    }

    static func lanczosKernel(_ d: Double, _ a: Int) -> Double {
        if abs(d) < 1e-12 { return 1 }
        let A = Double(a)
        if abs(d) >= A { return 0 }
        let pd = Double.pi * d
        return A * sin(pd) * sin(pd / A) / (pd * pd)
    }

    /// Band-limited resampling (Lanczos, a = 6). Output sample i sits at time i / fsOut.
    static func resampleLanczos(_ x: [Double], fsIn: Double, fsOut: Double, a: Int = 6) -> [Double] {
        let n = x.count
        guard n > 1, fsIn > 0, fsOut > 0 else { return x }
        let m = Int((Double(n) * fsOut / fsIn).rounded())
        var y = [Double](repeating: 0, count: m)
        let r = fsIn / fsOut
        for i in 0..<m {
            let pos = Double(i) * r
            let c = Int(pos.rounded(.down))
            var s = 0.0, ws = 0.0
            for j in (c - a + 1)...(c + a) {
                let w = lanczosKernel(pos - Double(j), a)
                if w == 0 { continue }
                let jj = min(max(j, 0), n - 1)
                s += w * x[jj]
                ws += w
            }
            y[i] = ws != 0 ? s / ws : 0
        }
        return y
    }

    /// Moving average, like numpy.convolve(x, ones(w)/w, mode="same").
    static func movavg(_ x: [Double], _ w0: Int) -> [Double] {
        let w = max(w0, 1), n = x.count
        guard n > 0 else { return [] }
        var cs = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { cs[i + 1] = cs[i] + x[i] }
        let h = (w - 1) / 2
        var y = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let hi = min(n - 1, i + h)
            let lo = max(0, i + h - (w - 1))
            y[i] = hi >= lo ? (cs[hi + 1] - cs[lo]) / Double(w) : 0
        }
        return y
    }

    /// Magnitude of the analytic signal (Hilbert envelope).
    static func analyticEnv(_ x: [Double]) -> [Double] {
        let n = x.count
        guard n > 1 else { return x.map { abs($0) } }
        let nn = nextPow2(n)
        var re = x
        re.append(contentsOf: [Double](repeating: 0, count: nn - n))
        var im = [Double](repeating: 0, count: nn)
        fft(&re, &im, inverse: false)
        let half = nn / 2
        if half > 1 { for k in 1..<half { re[k] *= 2; im[k] *= 2 } }
        if half + 1 < nn { for k in (half + 1)..<nn { re[k] = 0; im[k] = 0 } }
        fft(&re, &im, inverse: true)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n { out[i] = sqrt(re[i] * re[i] + im[i] * im[i]) }
        return out
    }

    /// Dominant frequency (Hz) between lo and hi, Hann window, 4x zero padding.
    static func dominantHR(_ x: [Double], fs: Double, lo: Double = 0.7, hi: Double = 3.5) -> Double {
        let m0 = x.count
        guard m0 > 8, fs > 0 else { return .nan }
        let mu = mean(x)
        let nn = nextPow2(m0 * 4)
        var re = [Double](repeating: 0, count: nn)
        var im = [Double](repeating: 0, count: nn)
        for i in 0..<m0 {
            let v = x[i].isFinite ? x[i] - mu : 0
            re[i] = v * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(m0 - 1)))
        }
        fft(&re, &im, inverse: false)
        var best = Double.nan, bv = -1.0
        for k in 0...(nn / 2) {
            let f = Double(k) * fs / Double(nn)
            if f >= lo && f <= hi {
                let mag = re[k] * re[k] + im[k] * im[k]
                if mag > bv { bv = mag; best = f }
            }
        }
        return best
    }

    /// Spectral peak / median in a band (heartbeat clarity), Hann window.
    static func spectralPeakRatio(_ x: [Double], fs: Double, lo: Double, hi: Double) -> Double {
        let m0 = x.count
        guard m0 > 8, fs > 0 else { return 0 }
        let nn = nextPow2(m0)
        var re = [Double](repeating: 0, count: nn)
        var im = [Double](repeating: 0, count: nn)
        for i in 0..<m0 { re[i] = x[i] * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(m0 - 1))) }
        fft(&re, &im, inverse: false)
        var mags: [Double] = []
        for k in 0...(nn / 2) {
            let f = Double(k) * fs / Double(nn)
            if f > lo && f < hi { mags.append(sqrt(re[k] * re[k] + im[k] * im[k])) }
        }
        guard let mx = mags.max() else { return 0 }
        return mx / (median(mags) + 1e-12)
    }

    // MARK: peaks

    static func localMax(_ x: [Double]) -> [Int] {
        guard x.count >= 3 else { return [] }
        var r: [Int] = []
        for i in 1..<(x.count - 1) where x[i] > x[i - 1] && x[i] >= x[i + 1] { r.append(i) }
        return r
    }

    static func prominence(_ x: [Double], _ i: Int, _ wl: Int) -> Double {
        let n = x.count
        let a = max(0, i - wl), b = min(n, i + wl + 1)
        let v = x[i]
        var lmin = v
        var j = i
        while j >= a {
            if x[j] > v { break }
            lmin = min(lmin, x[j])
            j -= 1
        }
        var rmin = v
        j = i
        while j < b {
            if x[j] > v { break }
            rmin = min(rmin, x[j])
            j += 1
        }
        return v - max(lmin, rmin)
    }

    static func findPeaks(_ x: [Double], distance: Int, wl: Int, minRelProm: Double) -> [Int] {
        let c = localMax(x)
        guard !c.isEmpty else { return [] }
        let order = c.sorted { x[$0] > x[$1] }
        var taken = [Bool](repeating: false, count: x.count)
        var keep: [Int] = []
        for i in order {
            if taken[i] { continue }
            keep.append(i)
            let a = max(0, i - distance), b = min(x.count - 1, i + distance)
            if b >= a { for j in a...b { taken[j] = true } }
        }
        keep.sort()
        if minRelProm > 0 && !keep.isEmpty {
            let pr = keep.map { prominence(x, $0, wl) }
            let thr = minRelProm * median(pr)
            var out: [Int] = []
            for (k, p) in Swift.zip(keep, pr) where p >= thr { out.append(k) }
            keep = out
        }
        return keep
    }

    // MARK: matrices

    static func columnPercentile(_ rows: [[Double]], _ q: Double) -> [Double] {
        guard let width = rows.first?.count, width > 0 else { return [] }
        var out = [Double](repeating: .nan, count: width)
        var col = [Double](repeating: 0, count: rows.count)
        for j in 0..<width {
            for (i, r) in rows.enumerated() { col[i] = j < r.count ? r[j] : .nan }
            out[j] = percentile(col, q)
        }
        return out
    }

    static func columnMedian(_ rows: [[Double]]) -> [Double] { columnPercentile(rows, 50) }

    static func cov3(_ m: [[Double]]) -> [[Double]] {
        var c = [[Double]](repeating: [0, 0, 0], count: 3)
        guard m.count == 3 else { return c }
        let n = m.map { $0.count }.min() ?? 0
        guard n > 1 else { return c }
        var mu = [0.0, 0.0, 0.0]
        for i in 0..<3 {
            var s = 0.0
            for k in 0..<n { s += m[i][k] }
            mu[i] = s / Double(n)
        }
        for i in 0..<3 {
            for j in i..<3 {
                var s = 0.0
                for k in 0..<n { s += (m[i][k] - mu[i]) * (m[j][k] - mu[j]) }
                c[i][j] = s / Double(n - 1)
                c[j][i] = c[i][j]
            }
        }
        return c
    }

    /// Dominant eigenvector of a symmetric 3x3 matrix (power iteration).
    static func topEigenvector3(_ c: [[Double]]) -> [Double] {
        var v = [0.3, 0.5, 0.81]
        for _ in 0..<300 {
            var w = [0.0, 0.0, 0.0]
            for i in 0..<3 { for j in 0..<3 { w[i] += c[i][j] * v[j] } }
            let nrm = sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2])
            if !(nrm > 1e-30) { return [0, 0, -1] }
            v = [w[0] / nrm, w[1] / nrm, w[2] / nrm]
        }
        return v
    }

    // MARK: beat-locked ratio

    static func segments(_ s: [Double], th0: Double, fs: Double, times: [Double], pre: Int, post: Int) -> [[Double]] {
        var out: [[Double]] = []
        for t in times where t.isFinite {
            let c = Int(((t - th0) * fs).rounded())
            if c - pre >= 0 && c + post < s.count { out.append(Array(s[(c - pre)..<(c + post)])) }
        }
        return out
    }

    /// How strongly the SCG contains a component time-locked to the finger pulse.
    /// Ratio = energy of the beat-aligned average / energy of averages at random times (about 1 = nothing).
    /// winS = (start, end) in seconds relative to the finger-pulse foot: only look for the burst there.
    /// Use (-0.4, -0.06), where the AO is searched, so a finger-pulse leak just after the foot can't count.
    static func beatLock(_ s: [Double], th0: Double, fs: Double, times: [Double], seed: UInt64 = 0,
                         winS: (Double, Double)? = nil)
        -> (snrDb: Double, ratio: Double, template: [Double], count: Int) {
        let pre = Int(0.5 * fs), post = Int(0.1 * fs)
        let segs = segments(s, th0: th0, fs: fs, times: times, pre: pre, post: post)
        guard segs.count >= 5 else { return (.nan, .nan, [], segs.count) }
        let m = columnMedian(segs)
        let width = m.count
        var wa = 0
        var wb = width
        if let win = winS {
            wa = max(0, pre + Int((win.0 * fs).rounded()))
            wb = min(width, pre + Int((win.1 * fs).rounded()) + 1)
        }
        if wb <= wa {
            wa = 0
            wb = width
        }
        let w = max(1, Int(0.06 * fs))
        func peakEnergy(_ x: [Double]) -> Double {
            let ex = movavg(x.map { $0 * $0 }, w)
            var mx = -Double.infinity
            var i = wa
            while i < min(wb, ex.count) {
                if ex[i] > mx { mx = ex[i] }
                i += 1
            }
            return mx.isFinite ? mx : .nan
        }
        let e = movavg(m.map { $0 * $0 }, w)
        let j = argmax(e, wa, min(wb, e.count))
        let a = max(0, j - w / 2), b = min(m.count, j + w / 2)
        var snr = Double.nan
        if b > a {
            var num = 0.0, den = 0.0
            for k in a..<b { num += m[k] * m[k] }
            for row in segs { for k in a..<b { let d = row[k] - m[k]; den += d * d } }
            if den > 0 { snr = 10 * log10((num / Double(b - a)) / (den / Double((b - a) * segs.count))) }
        }
        var rng = SplitMix64(state: seed &+ 0x5EED)
        let tEnd = th0 + Double(s.count - 1) / fs
        var ctrl: [Double] = []
        if tEnd - 0.2 > th0 + 0.6 {
            for _ in 0..<5 {
                var ts: [Double] = []
                for _ in 0..<segs.count { ts.append(rng.uniform(th0 + 0.6, tEnd - 0.2)) }
                let r = segments(s, th0: th0, fs: fs, times: ts, pre: pre, post: post)
                if !r.isEmpty { ctrl.append(peakEnergy(columnMedian(r))) }
            }
        }
        let c = median(ctrl)
        let ratio = c > 0 ? peakEnergy(m) / c : .nan
        return (snr, ratio, m, segs.count)
    }
}

/// Small deterministic random generator (so the same recording always gives the same ratio).
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ a: Double, _ b: Double) -> Double {
        a + (b - a) * Double(next() >> 11) / 9_007_199_254_740_992.0
    }
}
