#!/usr/bin/env python3
"""
HyperChat Capture - feasibility analysis
SCG (phone accelerometer, chest) + camera PPG (fingertip) -> AO, PTT, PIR

Needs only: numpy, pandas, matplotlib   (pip install numpy pandas matplotlib)

Usage
  python hc_analyze.py SESSION_FOLDER                 # one recording
  python hc_analyze.py --all RECORDINGS_FOLDER        # every recording + cross-session table
Options
  --ppg-channel r|g|b      force the PPG colour channel (default: auto)
  --explore-polarity       also test the flipped SCG sign (only if placement differed from protocol;
                           a flipped sign shifts AO by ~30 ms with equally "stable" PTT, so never pick it by ranking)

Outputs are written inside each session folder, in  analysis/ :
  summary.txt, combos.csv, beats_best.csv, overview.png, ensemble.png, ptt_pir.png
With --all, all_sessions.csv and cross_session.txt are written in RECORDINGS_FOLDER.

RESEARCH PROTOTYPE. Not a medical device. Do not act on any number produced here.
"""
import argparse, glob, json, os, sys
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

CFG = dict(
    fs_hi=1000.0,                       # Hz, analysis grid (interpolate before differentiating)
    ppg_band=(0.5, 10.0),               # Hz
    scg_bands=[(1.0, 20.0), (5.0, 40.0)],  # Seismo-like, AlwaysBP-like (upper edge capped by Nyquist)
    ptt_range=(0.060, 0.400),           # s, plausible AO -> fingertip window
    min_valid_beats=15,
    polarities=(+1,),                   # +1 = out of the chest, phone screen against chest. --explore-polarity adds -1
    fixed_band_index=1,                 # version 2: the 5-40 Hz band decides the heartbeat check and the fixed PTT
    edge_trim=1.0,                      # s dropped at both ends of the record phase
)
FEATURES = ["apg_peak", "tangent_foot", "max_slope"]
METHODS = ["rule", "ensemble", "scg_first"]


# ----------------------------------------------------------------------------- signal helpers
def uniform(t, x, fs, t0, t1):
    """Linear resample of irregular samples onto a uniform grid [t0, t1)."""
    tg = t0 + np.arange(int(np.floor((t1 - t0) * fs))) / fs
    return tg, np.interp(tg, t, x)


def _mask(n, fs, lo, hi):
    f = np.fft.rfftfreq(n, 1.0 / fs)
    m = np.ones_like(f)
    if lo and lo > 0:
        w = max(0.25 * lo, 0.15)
        m *= np.clip((f - (lo - w)) / w, 0, 1)
        m = np.where((f > lo - w) & (f < lo), 0.5 - 0.5 * np.cos(np.pi * (f - (lo - w)) / w), m)
    if hi is not None:
        hi = min(hi, 0.45 * fs)
        w = max(0.15 * hi, 0.5)
        m = np.where(f >= hi + w, 0, m)
        sel = (f > hi) & (f < hi + w)
        m[sel] *= 0.5 + 0.5 * np.cos(np.pi * (f[sel] - hi) / w)
    return m


def filt_up(x, fs, lo, hi, fs_out=None, pad_s=2.0):
    """Zero-phase FFT band-pass (lo=0 keeps DC), optional band-limited upsampling.
    Returns signal at fs_out (or fs) covering exactly the input span."""
    x = np.asarray(x, float)
    n0 = len(x)
    p = min(int(pad_s * fs), n0 - 1)
    xp = np.concatenate([x[p:0:-1], x, x[-2:-p - 2:-1]])
    if lo and lo > 0:
        tt = np.arange(len(xp))
        xp = xp - np.polyval(np.polyfit(tt, xp, 1), tt)
    X = np.fft.rfft(xp) * _mask(len(xp), fs, lo, hi)
    if fs_out is None or fs_out == fs:
        y = np.fft.irfft(X, n=len(xp))
        return y[p:p + n0]
    k = fs_out / fs
    m = int(round(len(xp) * k))
    Y = np.zeros(m // 2 + 1, complex)
    nb = min(len(X), len(Y))
    Y[:nb] = X[:nb]
    y = np.fft.irfft(Y, n=m) * (m / len(xp))
    s = int(round(p * k))
    return y[s:s + int(round(n0 * k))]


def analytic_env(x):
    n = len(x)
    X = np.fft.fft(x)
    h = np.zeros(n)
    h[0] = 1
    if n % 2 == 0:
        h[n // 2] = 1
        h[1:n // 2] = 2
    else:
        h[1:(n + 1) // 2] = 2
    return np.abs(np.fft.ifft(X * h))


def movavg(x, w):
    w = max(int(w), 1)
    return np.convolve(x, np.ones(w) / w, mode="same")


def dominant_hr(x, fs, lo=0.7, hi=3.5):
    x = x - np.mean(x)
    n = int(2 ** np.ceil(np.log2(len(x) * 4)))
    F = np.abs(np.fft.rfft(x * np.hanning(len(x)), n))
    f = np.fft.rfftfreq(n, 1 / fs)
    sel = (f >= lo) & (f <= hi)
    return float(f[sel][np.argmax(F[sel])])


def local_max(x):
    return np.where((x[1:-1] > x[:-2]) & (x[1:-1] >= x[2:]))[0] + 1


def prominence(x, i, wl):
    a, b = max(0, i - wl), min(len(x), i + wl + 1)
    v = x[i]
    left = x[a:i + 1][::-1]
    hl = np.where(left > v)[0]
    lmin = left[:hl[0]].min() if len(hl) else left.min()
    right = x[i:b]
    hr = np.where(right > v)[0]
    rmin = right[:hr[0]].min() if len(hr) else right.min()
    return v - max(lmin, rmin)


def find_peaks(x, distance, wl, min_rel_prom=0.0):
    c = local_max(x)
    if len(c) == 0:
        return c
    order = c[np.argsort(-x[c])]
    keep = np.zeros(len(x), bool)
    taken = np.zeros(len(x), bool)
    for i in order:
        if not taken[i]:
            keep[i] = True
            taken[max(0, i - distance):i + distance + 1] = True
    pk = np.where(keep)[0]
    if min_rel_prom > 0 and len(pk):
        pr = np.array([prominence(x, i, wl) for i in pk])
        pk = pk[pr >= min_rel_prom * np.median(pr)]
    return pk


def robust_sd(x):
    x = np.asarray(x, float)
    x = x[np.isfinite(x)]
    return float(1.4826 * np.median(np.abs(x - np.median(x)))) if len(x) else np.nan


# ----------------------------------------------------------------------------- loading
def load_session(folder):
    meta = json.load(open(os.path.join(folder, "meta.json")))
    ppg = pd.read_csv(os.path.join(folder, "ppg.csv"))
    acc = pd.read_csv(os.path.join(folder, "acc.csv"))
    gyro_p = os.path.join(folder, "gyro.csv")
    gyro = pd.read_csv(gyro_p) if os.path.exists(gyro_p) else None
    mk_p = os.path.join(folder, "markers.csv")
    markers = pd.read_csv(mk_p) if os.path.exists(mk_p) else pd.DataFrame(columns=["t", "label"])
    return meta, ppg, acc, gyro, markers


def rate_report(t, name):
    dt = np.diff(t)
    med = np.median(dt)
    return dict(stream=name, n=len(t), rate_hz=1 / med, jitter_ms=1000 * robust_sd(dt),
                gaps=int(np.sum(dt > 1.5 * med)), longest_gap_ms=1000 * dt.max())


# ----------------------------------------------------------------------------- PPG
def ppg_process(ppg, t0, t1, fs_hi, channel=None):
    t = ppg["t"].to_numpy()
    fs = 1 / np.median(np.diff(t))
    fs = round(fs)
    info = {}
    best, best_score = None, -1
    for c in ["r", "g", "b"]:
        tg, L = uniform(t, ppg[c].to_numpy(), fs, t0, t1)
        ac = filt_up(L, fs, 0.7, 3.5)
        dc = np.mean(L)
        puls = np.std(ac) / dc if dc > 1 else 0
        hr_peak = 0
        if np.std(ac) > 0:
            F = np.abs(np.fft.rfft(ac * np.hanning(len(ac))))
            f = np.fft.rfftfreq(len(ac), 1 / fs)
            band = (f > 0.7) & (f < 3.5)
            hr_peak = F[band].max() / (np.median(F[band]) + 1e-12)
        info[c] = dict(mean=float(dc), pulsatility_pct=100 * puls, spectral_peak_ratio=float(hr_peak))
        ok = 5 < dc < 250
        score = puls * np.log1p(hr_peak) if ok else 0
        if score > best_score:
            best, best_score = c, score
    ch = channel or best
    tg, L = uniform(t, ppg[ch].to_numpy(), fs, t0, t1)
    sat_col = "sat_any" if "sat_any" in ppg else None
    sat = uniform(t, ppg[sat_col].to_numpy(), fs, t0, t1)[1] if sat_col else np.zeros_like(L)
    v_nat = -filt_up(L, fs, *CFG["ppg_band"])          # volume-oriented (more blood = up)
    hr = dominant_hr(v_nat, fs)
    v = -filt_up(L, fs, *CFG["ppg_band"], fs_out=fs_hi)
    Llp = filt_up(L, fs, 0, CFG["ppg_band"][1], fs_out=fs_hi)  # DC kept, for PIR
    th = t0 + np.arange(len(v)) / fs_hi
    sat_hi = np.interp(th, tg, sat)
    return dict(t=th, v=v, L=Llp, sat=sat_hi, fs_native=fs, hr_hz=hr, channel=ch,
                channel_info=info, raw_t=tg, raw_L=L)


def ppg_beats(P, fs_hi):
    v, t = P["v"], P["t"]
    T = 1 / P["hr_hz"]
    d1 = np.gradient(v) * fs_hi
    d2 = np.gradient(d1) * fs_hi
    pk = find_peaks(v, int(0.6 * T * fs_hi), int(1.5 * T * fs_hi), min_rel_prom=0.3)
    rows = []
    for i in pk:
        a = max(0, i - int(0.5 * T * fs_hi))
        if i - a < 10:
            continue
        foot = a + int(np.argmin(v[a:i]))
        if i - foot < 5:
            continue
        ms = foot + int(np.argmax(d1[foot:i]))
        tan = t[ms] - (v[ms] - v[foot]) / d1[ms] if d1[ms] > 0 else np.nan
        b = max(0, foot - int(0.08 * fs_hi))
        apg = b + int(np.argmax(d2[b:ms + 1]))
        rows.append(dict(peak_i=i, foot_i=foot, t_peak=t[i], t_foot=t[foot], max_slope=t[ms],
                         tangent_foot=tan, apg_peak=t[apg], amp=v[i] - v[foot]))
    B = pd.DataFrame(rows)
    if len(B) < 3:
        return B
    # PIR on DC-inclusive light: light is highest at the feet (least blood), lowest at the systolic peak
    L = P["L"]
    w = int(0.03 * fs_hi)
    pir = []
    for k in range(len(B)):
        if k + 1 >= len(B):
            pir.append(np.nan); continue
        f1, f2, pkk = B.foot_i[k], B.foot_i[k + 1], B.peak_i[k]
        l1 = L[max(0, f1 - w):f1 + w].max()
        l2 = L[max(0, f2 - w):f2 + w].max()
        lp = L[max(0, pkk - w):pkk + w].min()
        pir.append((l1 + l2) / (2 * lp) if lp > 0 else np.nan)
    B["pir"] = pir
    B["ibi"] = np.append(np.diff(B.t_peak.to_numpy()), np.nan)
    B["sat"] = [P["sat"][max(0, f):p + 1].max() for f, p in zip(B.foot_i, B.peak_i)]
    med_ibi, med_amp = np.nanmedian(B.ibi), np.median(B.amp)
    B["ppg_ok"] = ((B.sat < 0.02) & (B.amp > 0.4 * med_amp) & (B.amp < 2.5 * med_amp) &
                   ((B.ibi.isna()) | ((B.ibi - med_ibi).abs() < 0.25 * med_ibi)))
    return B


# ----------------------------------------------------------------------------- finger colour quality
def channel_quality(t, x, fs, t0, t1):
    """Is this colour a real, clean heartbeat and not noise? Same checks as the app (0.3.3)."""
    tg, L = uniform(t, x, fs, t0, t1)
    q = dict(mean=float(np.mean(L)), beats=0, ok=0, peak_ratio=0.0, ibi_cv=np.nan, shape=np.nan, agree=None)
    if len(L) < 10 * fs:
        return q, np.array([])
    ac = filt_up(L, fs, 0.7, 3.5)
    if np.std(ac) > 0:
        F = np.abs(np.fft.rfft(ac * np.hanning(len(ac))))
        f = np.fft.rfftfreq(len(ac), 1 / fs)
        band = (f > 0.7) & (f < 3.5)
        q["peak_ratio"] = float(F[band].max() / (np.median(F[band]) + 1e-12))
    v = -filt_up(L, fs, 0.5, 10)
    hr = dominant_hr(v, fs)
    T = 1 / hr
    feet, peaks = [], []
    for i in find_peaks(v, int(0.6 * T * fs), int(1.5 * T * fs), 0.3):
        a = max(0, i - int(0.5 * T * fs))
        if i - a < 3:
            continue
        f0 = a + int(np.argmin(v[a:i]))
        if i - f0 < 2:
            continue
        feet.append(f0); peaks.append(i)
    feet, peaks = np.array(feet), np.array(peaks)
    q["beats"] = len(feet)
    if len(feet) < 5:
        return q, np.array([])
    amps = v[peaks] - v[feet]
    ibi = np.diff(feet) / fs
    mA, mI = np.median(amps), np.median(ibi)
    ib = np.append(ibi, np.nan)
    ok = (amps > 0.4 * mA) & (amps < 2.5 * mA) & (np.isnan(ib) | (np.abs(ib - mI) < 0.25 * mI))
    q["ok"] = int(ok.sum())
    q["ibi_cv"] = 100 * robust_sd(ibi) / mI
    pre, post = int(0.1 * T * fs), int(0.6 * T * fs)
    segs = []
    for f0 in feet[ok]:
        if f0 - pre >= 0 and f0 + post <= len(v):
            s = v[f0 - pre:f0 + post]
            if np.std(s) > 0:
                segs.append((s - s.mean()) / s.std())
    if len(segs) >= 5:
        S = np.array(segs)
        tm = np.median(S, axis=0)
        if np.std(tm) > 0:
            q["shape"] = float(np.median(S @ ((tm - tm.mean()) / tm.std()) / S.shape[1]))
    # times used to check that red and green see the same beats: the pulse peak (steadier than the lowest point)
    return q, (t0 + peaks[ok] / fs, t0 + peaks / fs)


def judge(q):
    why = []
    if not q["mean"] >= 10: why.append("too dark")
    if q["mean"] > 245: why.append("too bright")
    if q["ok"] < 15: why.append("too few clean beats")
    elif q["ok"] < 0.6 * q["beats"]: why.append("many irregular beats")
    if not q["peak_ratio"] >= 5: why.append("heartbeat rhythm not clear")
    if not q["ibi_cv"] <= 15: why.append("beat timing irregular")
    if not q["shape"] >= 0.8: why.append("beat shape inconsistent")
    if q["agree"] is not None and q["agree"] < 70: why.append("beats don't match the other colour")
    q["passed"] = not why
    q["reason"] = ", ".join(why)


def assess_colours(ppg, t0, t1):
    t = ppg["t"].to_numpy()
    fs = round(1 / np.median(np.diff(t)))
    Q, F, FA = {}, {}, {}
    for c in "rgb":
        Q[c], ft = channel_quality(t, ppg[c].to_numpy(), fs, t0, t1)
        F[c], FA[c] = ft if isinstance(ft, tuple) else (ft, ft)
        judge(Q[c])
    # version 2: compare with every pulse found in the other colour (not only its clean ones),
    # as long as that colour is bright enough and found at least 15 pulses
    for c, o in (("r", "g"), ("g", "r")):
        if Q[o]["mean"] >= 10 and Q[o]["beats"] >= 15 and len(F[c]) and len(FA[o]):
            Q[c]["agree"] = 100 * float(np.mean([np.min(np.abs(FA[o] - x)) <= 0.05 for x in F[c]]))
    for c in "rgb":
        judge(Q[c])
    return Q


def best_colour(Q):
    """Most consistent beat shape; if within 0.02, larger share of clean beats; if within 2 points, clearer rhythm."""
    import functools
    passing = [c for c in "rgb" if Q[c]["passed"]]
    share = lambda c: Q[c]["ok"] / Q[c]["beats"] if Q[c]["beats"] else 0

    def cmp(a, b):
        if abs(Q[a]["shape"] - Q[b]["shape"]) > 0.02:
            return -1 if Q[a]["shape"] > Q[b]["shape"] else 1
        if abs(share(a) - share(b)) > 0.02:
            return -1 if share(a) > share(b) else 1
        return -1 if Q[a]["peak_ratio"] > Q[b]["peak_ratio"] else 1
    passing.sort(key=functools.cmp_to_key(cmp))
    return passing[0] if passing else None


# ----------------------------------------------------------------------------- SCG
def scg_axes(acc, t0, t1, fs_hi):
    t = acc["t"].to_numpy()
    fs = round(1 / np.median(np.diff(t)))
    out = {}
    raw = {}
    for a in "xyz":
        raw[a] = uniform(t, acc[a].to_numpy(), fs, t0, t1)[1]
    for lo, hi in CFG["scg_bands"]:
        hi_eff = min(hi, 0.45 * fs)
        key = f"{lo:g}-{hi_eff:g}Hz"
        nat = {a: filt_up(raw[a], fs, lo, hi_eff) for a in "xyz"}
        M = np.vstack([nat["x"], nat["y"], nat["z"]])
        w, V = np.linalg.eigh(np.cov(M))
        pc = V[:, -1]
        if pc[2] < 0:           # align with +z: iOS reports minus the acceleration, so with the screen against
            pc = -pc            # the chest the out-of-chest movement shows as +z (fixed in version 2)
        up = {a: filt_up(raw[a], fs, lo, hi_eff, fs_out=fs_hi) for a in "xyz"}
        out[(key, "dv")] = up["z"]
        out[(key, "pca")] = pc[0] * up["x"] + pc[1] * up["y"] + pc[2] * up["z"]
        out[(key, "pca_dir")] = pc
    th = t0 + np.arange(len(out[(key, "dv")])) / fs_hi
    grav = {a: float(np.mean(raw[a])) for a in "xyz"}
    return out, th, fs, grav


def scg_hr(s, fs_hi):
    env = movavg(analytic_env(s), 0.05 * fs_hi)
    ds = int(fs_hi // 50)
    return dominant_hr(env[::ds], fs_hi / ds), env


def rule_ao(seg, fs_hi, rel=0.05):
    """Seismo-style: IM = most prominent negative peak (earlier one if >=90%), AO = next positive peak."""
    if len(seg) < 10:
        return None
    rng = seg.max() - seg.min()
    neg = local_max(-seg)
    if len(neg) == 0:
        return None
    pr = np.array([prominence(-seg, i, len(seg)) for i in neg])
    keep = pr >= rel * rng
    neg, pr = neg[keep], pr[keep]
    if len(neg) == 0:
        return None
    j = int(np.argmax(pr))
    if j > 0 and pr[j - 1] >= 0.9 * pr[j]:
        j -= 1
    im = neg[j]
    pos = local_max(seg)
    pos = pos[(pos > im) & (pos <= im + int(0.06 * fs_hi))]
    if len(pos) == 0:
        return None
    ppr = np.array([prominence(seg, i, len(seg)) for i in pos])
    pos = pos[ppr >= 4 * rel * rng]          # ignore noise wiggles
    return int(pos[0]) if len(pos) else None


def maxpos_ao(seg, fs_hi, rel=0.2):
    """AO = most prominent positive peak that has a negative peak (IM) within 60 ms before it."""
    if len(seg) < 10:
        return None
    rng = seg.max() - seg.min()
    pos = local_max(seg)
    if len(pos) == 0:
        return None
    pr = np.array([prominence(seg, i, len(seg)) for i in pos])
    neg = local_max(-seg)
    nw = int(0.06 * fs_hi)
    best, bp = None, 0
    for i, p in zip(pos, pr):
        if p >= rel * rng and p > bp and np.any((neg < i) & (neg >= i - nw)):
            best, bp = i, p
    return int(best) if best is not None else None


def detect_ao(method, s, th, beats, feat, fs_hi, T):
    lo, hi = CFG["ptt_range"]
    ft = beats[feat].to_numpy()
    n = len(ft)
    ao = np.full(n, np.nan)
    if method == "rule":
        for k in range(n):
            if not np.isfinite(ft[k]):
                continue
            a = int(round((ft[k] - hi - th[0]) * fs_hi))
            b = int(round((ft[k] - lo - th[0]) * fs_hi))
            if a < 0 or b >= len(s):
                continue
            r = rule_ao(s[a:b], fs_hi)
            if r is not None:
                ao[k] = th[a + r]
        return ao, None
    if method == "ensemble":
        pre, post = int(0.5 * fs_hi), int(0.1 * fs_hi)
        segs, idx = [], []
        for k in range(n):
            if not (np.isfinite(ft[k]) and beats.ok_pre[k]):
                continue
            c = int(round((ft[k] - th[0]) * fs_hi))
            if c - pre < 0 or c + post >= len(s):
                continue
            segs.append(s[c - pre:c + post]); idx.append(k)
        if len(segs) < 5:
            return ao, None
        S = np.array(segs)
        tmpl = np.median(S, axis=0)
        a = pre - int(hi * fs_hi); b = pre - int(lo * fs_hi)
        r = maxpos_ao(tmpl[a:b], fs_hi)
        if r is None:
            return ao, dict(template=tmpl, S=S, ao_i=None, pre=pre)
        ao_i = a + r
        w = int(0.08 * fs_hi); L = int(0.04 * fs_hi)
        ref = tmpl[ao_i - w:ao_i + w]
        for row, k in zip(S, idx):
            best, bl = -np.inf, 0
            for lag in range(-L, L + 1):
                sl = row[ao_i - w + lag:ao_i + w + lag]
                if len(sl) != len(ref):
                    continue
                cval = np.dot(sl - sl.mean(), ref - ref.mean())
                if cval > best:
                    best, bl = cval, lag
            j = ao_i + bl
            sn = int(0.01 * fs_hi)
            loc = row[max(0, j - sn):j + sn + 1]
            j = max(0, j - sn) + int(np.argmax(loc))
            ao[k] = ft[k] + (j - pre) / fs_hi
        return ao, dict(template=tmpl, S=S, ao_i=ao_i, pre=pre)
    if method == "scg_first":
        hr_s, env = scg_hr(s, fs_hi)
        Ts = 1 / hr_s
        if abs(Ts - T) > 0.1 * T:      # envelope rate unreliable -> use PPG rate for beat spacing only
            Ts = T
        ep = find_peaks(env, int(0.6 * Ts * fs_hi), int(1.5 * Ts * fs_hi), min_rel_prom=0.3)
        aos = []
        w = int(0.08 * fs_hi)
        for e in ep:
            seg = s[max(0, e - w):e + w]
            if len(seg):
                aos.append(th[max(0, e - w) + int(np.argmax(seg))])
        aos = np.array(aos)
        for k in range(n):
            if not np.isfinite(ft[k]):
                continue
            d = ft[k] - aos
            c = np.where((d >= lo) & (d <= hi))[0]
            if len(c):
                ao[k] = aos[c[np.argmin(np.abs(d[c] - np.median(d[c])))]] if len(c) > 1 else aos[c[0]]
        return ao, dict(hr_scg=hr_s * 60)
    raise ValueError(method)


def beat_locked(s, th, times, fs_hi, seed=0, win=None):
    """How strongly the SCG contains a component time-locked to the finger pulse.
    Ratio = energy of the beat-aligned average / energy of averages at random times (~1 = nothing).
    win = (start, end) in s relative to the finger-pulse foot: only look for the burst there.
    Use win=(-0.4, -0.06) (where the AO is searched) so a finger-pulse leak just after the foot can't count."""
    pre, post = int(0.5 * fs_hi), int(0.1 * fs_hi)
    a = 0 if win is None else max(0, pre + int(round(win[0] * fs_hi)))
    b = pre + post if win is None else min(pre + post, pre + int(round(win[1] * fs_hi)) + 1)

    def tmpl(ts):
        seg = []
        for t_ in ts:
            c = int(round((t_ - th[0]) * fs_hi))
            if c - pre >= 0 and c + post < len(s):
                seg.append(s[c - pre:c + post])
        return np.array(seg)
    A = tmpl(times)
    if len(A) < 5:
        return np.nan, np.nan
    m = np.median(A, axis=0)
    w = int(0.06 * fs_hi)
    peak_e = lambda x: float(np.max(movavg(x ** 2, w)[a:b]))     # energy of the strongest 60 ms burst in the window
    j = a + int(np.argmax(movavg(m ** 2, w)[a:b]))
    sl = slice(max(0, j - w // 2), j + w // 2)
    snr_db = 10 * np.log10(np.mean(m[sl] ** 2) / np.mean((A[:, sl] - m[sl]) ** 2))
    rng = np.random.default_rng(seed)
    ctrl = [peak_e(np.median(tmpl(rng.uniform(th[0] + 0.6, th[-1] - 0.2, len(A))), axis=0)) for _ in range(5)]
    return snr_db, peak_e(m) / float(np.median(ctrl))


# ----------------------------------------------------------------------------- tap sync test
def tap_sync(acc, P, t0, t1):
    """Accelerometer taps first; then, within 0.25 s of each, the unfiltered camera frame-to-frame light change
    is searched for a jump clearly bigger than a heartbeat (2.5x the median heartbeat jump). Camera events are
    only counted next to accelerometer taps, so heartbeats can't be mistaken for taps. Same as the app (0.3.1)."""
    t = acc["t"].to_numpy()
    fs = round(1 / np.median(np.diff(t)))
    mag = np.sqrt(sum(uniform(t, acc[a].to_numpy(), fs, t0, t1)[1] ** 2 for a in "xyz"))
    hp = np.abs(filt_up(mag, fs, 5, 0.45 * fs))
    ta = t0 + np.arange(len(hp)) / fs

    def events(x, tt, k):
        thr = np.median(x) + k * 1.4826 * np.median(np.abs(x - np.median(x)))
        ev = []
        for i in np.where(x > thr)[0]:
            if not ev or tt[i] - ev[-1] > 0.3:
                ev.append(tt[i])
        return np.array(ev)

    # jolts < 0.3 s apart = one burst; bursts < 0.5 s apart (lift-off + landing, or a bounce) merged,
    # keeping the stronger, timed at its onset
    thrA = np.median(hp) + 7 * 1.4826 * np.median(np.abs(hp - np.median(hp)))
    subs = []
    for i in np.where(hp > thrA)[0]:
        if subs and ta[i] - ta[subs[-1][2]] <= 0.3:
            subs[-1][2] = i; subs[-1][1] = max(subs[-1][1], hp[i])
        else:
            subs.append([i, hp[i], i])
    merged = []
    for sb in subs:
        if merged and ta[sb[0]] - ta[merged[-1][0]] <= 0.5:
            if sb[1] > merged[-1][1]:
                merged[-1] = sb
        else:
            merged.append(sb)
    ea = np.array([ta[sb[0]] for sb in merged])
    L, rt, fsp = P["raw_L"], P["raw_t"], P["fs_native"]
    d = np.diff(L)
    dL = np.abs(0.5 * (d + np.concatenate([[0.0], d[:-1]])))
    tt = rt[1:]
    T = 1 / P["hr_hz"]
    pk = find_peaks(dL, int(0.6 * T * fsp), int(1.5 * T * fsp), 0.0)
    thr = 2.5 * (np.median(dL[pk]) if len(pk) else np.median(dL))
    off = []
    for e in ea:
        best, bd = -1, np.inf
        for j in np.where((tt >= e - 0.25) & (tt <= e + 0.25))[0]:
            if 0 < j < len(dL) - 1 and dL[j] >= thr and dL[j] >= dL[j - 1] and dL[j] >= dL[j + 1] and abs(tt[j] - e) < bd:
                best, bd = j, abs(tt[j] - e)
        if best >= 0:
            off.append(tt[best] - e)
    return dict(acc_taps=len(ea), ppg_events=len(off), paired=len(off),
                offset_median_ms=1000 * float(np.median(off)) if off else np.nan,
                offset_sd_ms=1000 * float(np.std(off)) if len(off) > 1 else np.nan)


# ----------------------------------------------------------------------------- Good / Weak grade (version 2)
GRADE = dict(lock_min=6.0, halves_min=0.8, second_max=0.75, spread_max_ms=10.0)


def grade_recording(lock, extra, row):
    """Good if: heartbeat clear, both halves of the beats give the same averaged heartbeat, one valve-opening
    bump stands out, PTT steady within the recording, and enough beats. Thresholds are judgement calls set
    on the first 6 chest recordings; they are judged on new recordings only."""
    g = dict(lock=lock, halves=np.nan, second=np.nan, ptt=np.nan, spread=np.nan, beats=0, reasons=[])
    if row is not None:
        g.update(ptt=float(row.ptt_median_ms), spread=float(row.ptt_robust_sd_ms), beats=int(row.valid))
    if extra and extra.get("S") is not None and len(extra["S"]) >= 6:
        S_, pre = extra["S"], extra["pre"]
        a, b = pre - int(CFG["ptt_range"][1] * CFG["fs_hi"]), pre - int(CFG["ptt_range"][0] * CFG["fs_hi"])
        mo, me = np.median(S_[1::2], axis=0)[a:b], np.median(S_[0::2], axis=0)[a:b]
        if np.std(mo) > 0 and np.std(me) > 0:
            g["halves"] = float(np.corrcoef(mo, me)[0, 1])
        ai = extra.get("ao_i")
        if ai is not None and a <= ai < b:
            seg = extra["template"][a:b]
            j = ai - a
            top = seg[j]
            rng = seg.max() - seg.min()
            others = [seg[i] for i in local_max(seg) if abs(i - j) > 15 and prominence(seg, i, len(seg)) >= 0.2 * rng]
            g["second"] = float(max(others) / top) if others and top > 0 else 0.0
    r = g["reasons"]
    if g["beats"] < CFG["min_valid_beats"]: r.append(f"fewer than {CFG['min_valid_beats']} good beats")
    if not lock > GRADE["lock_min"]: r.append(f"heartbeat not clear (ratio {lock:.1f})")
    if not g["halves"] >= GRADE["halves_min"]: r.append(f"beats not consistent (halves match {g['halves']:.2f})")
    if not (extra and extra.get("ao_i") is not None): r.append("valve-opening bump not found")
    elif not g["second"] < GRADE["second_max"]: r.append(f"two similar bumps (second {g['second']:.2f} of the first)")
    if not g["spread"] <= GRADE["spread_max_ms"]: r.append(f"PTT varies within the recording ({g['spread']:.1f} ms)")
    g["good"] = not r
    return g


# ----------------------------------------------------------------------------- one session
def analyze(folder, channel=None, verbose=True):
    meta, ppg, acc, gyro, markers = load_session(folder)
    outdir = os.path.join(folder, "analysis")
    os.makedirs(outdir, exist_ok=True)
    fs_hi = CFG["fs_hi"]
    rep = [rate_report(ppg.t.to_numpy(), "camera"), rate_report(acc.t.to_numpy(), "accelerometer")]
    if "phase" in ppg:
        ppg = ppg[ppg.phase == "record"]
        acc = acc[acc.phase == "record"]
    t0 = max(ppg.t.min(), acc.t.min()) + CFG["edge_trim"]
    t1 = min(ppg.t.max(), acc.t.max()) - CFG["edge_trim"]
    lines = [f"Session: {os.path.basename(os.path.normpath(folder))}   (hc_analyze version 2)",
             f"Mode: {meta.get('mode')}   Device: {meta.get('device_model')}   iOS {meta.get('os_version')}",
             f"Analysed span: {t1 - t0:.1f} s",
             "", "Capture quality"]
    for r in rep:
        lines.append(f"  {r['stream']:<13} {r['rate_hz']:7.1f} Hz  jitter {r['jitter_ms']:.2f} ms  "
                     f"gaps {r['gaps']}  longest {r['longest_gap_ms']:.1f} ms")
    if "iso" in ppg:
        lines.append(f"  camera ISO {ppg.iso.min():.0f}-{ppg.iso.max():.0f}, exposure "
                     f"{ppg.exp_ms.min():.2f}-{ppg.exp_ms.max():.2f} ms during record (should be constant)")

    Q = assess_colours(ppg, t0, t1)
    flags = list(meta.get("flags") or [])
    locked = meta.get("ppg_channel_locked")
    if channel:
        source, use = "forced on the command line", channel
    elif locked in ("r", "g", "b"):
        source, use = "saved colour", locked
    else:
        use = best_colour(Q)
        source = "chosen now" if use else "none passed; best available used"
    P = ppg_process(ppg, t0, t1, fs_hi, use)
    qu = Q[P["channel"]]
    if meta.get("mode") != "tap":
        if source == "saved colour" and not qu["passed"]:
            flags.append(f"The saved finger colour ({P['channel']}) failed the quality check: {qu['reason']}.")
        elif use is None:
            flags.append(f"The finger pulse failed the quality check in every colour ({P['channel']}: {qu['reason']}). "
                         "Results are unreliable.")
    lines.append("")
    lines.append("PPG channels (mean 0-255, pulsatility = AC/DC, peak ratio = heartbeat clarity)")
    for c, d in P["channel_info"].items():
        lines.append(f"  {c}: mean {d['mean']:6.1f}  pulsatility {d['pulsatility_pct']:.2f}%  "
                     f"peak ratio {d['spectral_peak_ratio']:.1f}" + ("   <- used" if c == P["channel"] else ""))
    lines.append(f"  PPG heart rate {60 * P['hr_hz']:.1f} bpm")
    lines.append(f"  Colour used: {P['channel']} ({source})")
    lines.append("  Quality per colour (clean beats, rhythm clarity, timing variation, beat shape, match with other colour):")
    for c in "rgb":
        q = Q[c]
        ag = "not checked" if q["agree"] is None else f"{q['agree']:.0f}%"
        lines.append(f"    {c}: {q['ok']}/{q['beats']}, clarity {q['peak_ratio']:.1f}, timing {q['ibi_cv']:.1f}%, "
                     f"shape {q['shape']:.3f}, match {ag} -> " + ("pass" if q["passed"] else "fail: " + q["reason"]))
    for f in flags:
        lines.append(f"  FLAGGED: {f}")
    summary = dict(session=os.path.basename(os.path.normpath(folder)), mode=meta.get("mode"),
                   cuff_sbp=meta.get("cuff_sbp"), cuff_dbp=meta.get("cuff_dbp"),
                   hr_ppg=60 * P["hr_hz"], ppg_channel=P["channel"],
                   cam_hz=rep[0]["rate_hz"], acc_hz=rep[1]["rate_hz"],
                   colour_source=source, colour_passed=bool(qu["passed"]), flagged=bool(flags),
                   colour_setup=meta.get("colour_setup"), placement=meta.get("placement", "sternum"))

    if meta.get("mode") == "tap":
        ts = tap_sync(acc, P, t0, t1)
        lines += ["", "Tap sync test",
                  f"  taps in accelerometer {ts['acc_taps']}, seen by the camera {ts['paired']}",
                  f"  PPG minus accelerometer offset: median {ts['offset_median_ms']:.1f} ms, "
                  f"SD {ts['offset_sd_ms']:.1f} ms",
                  "  (includes finger mechanics; a stable value across repeats matters more than zero)"]
        summary.update(ts)
        open(os.path.join(outdir, "summary.txt"), "w").write("\n".join(lines))
        if verbose:
            print("\n".join(lines))
        return summary

    B = ppg_beats(P, fs_hi)
    if len(B) < 5:
        lines.append("Too few PPG beats detected - check finger contact, torch and saturation.")
        open(os.path.join(outdir, "summary.txt"), "w").write("\n".join(lines))
        if verbose:
            print("\n".join(lines))
        return summary
    lines.append(f"  beats {len(B)}, passing PPG quality {int(B.ppg_ok.sum())}")
    pir_ok = B.pir[B.ppg_ok].dropna()
    lines.append(f"  PIR median {pir_ok.median():.4f}, robust CV {100 * robust_sd(pir_ok) / pir_ok.median():.2f}%")
    summary.update(pir_median=float(pir_ok.median()), pir_cv=float(100 * robust_sd(pir_ok) / pir_ok.median()),
                   n_beats=len(B), n_ppg_ok=int(B.ppg_ok.sum()))

    S, th, fs_acc, grav = scg_axes(acc, t0, t1, fs_hi)
    lines += ["", f"SCG  gravity (g): x {grav['x']:+.2f} y {grav['y']:+.2f} z {grav['z']:+.2f}"]
    if meta.get("mode") == "chest" and not (grav["y"] < -0.6 and abs(grav["x"]) < 0.5):
        f_up = (f"Phone not upright during the recording (gravity x {grav['x']:+.2f}, y {grav['y']:+.2f}): "
                "hold it with the long side along the breastbone, camera end towards your chin.")
        flags.append(f_up)
        lines.append(f"  FLAGGED: {f_up}")
        summary["flagged"] = True
    n = min(len(th), len(P["t"]))
    combos, store = [], {}
    for (band, axis), sig in S.items():
        if axis == "pca_dir":
            continue
        sig = sig[:n]
        hr_s, _ = scg_hr(sig, fs_hi)
        rms = []
        for ft in B.t_peak:
            c = int(round((ft - th[0]) * fs_hi))
            seg = sig[max(0, c - 500):c + 100]
            rms.append(np.sqrt(np.mean(seg ** 2)) if len(seg) else np.nan)
        rms = np.array(rms)
        motion_ok = rms < 2.5 * np.nanmedian(rms)
        for pol in CFG["polarities"]:
            s = pol * sig
            for feat in FEATURES:
                Bk = B.copy()
                Bk["ok_pre"] = (B.ppg_ok & motion_ok).to_numpy()
                for meth in METHODS:
                    ao, extra = detect_ao(meth, s, th[:n], Bk, feat, fs_hi, 1 / P["hr_hz"])
                    ptt = Bk[feat].to_numpy() - ao
                    valid = Bk.ok_pre.to_numpy() & np.isfinite(ptt) & (ptt >= CFG["ptt_range"][0]) & \
                        (ptt <= CFG["ptt_range"][1])
                    pv = ptt[valid] * 1000
                    half = len(pv) // 2
                    row = dict(method=meth, band=band, axis=axis, polarity="+" if pol > 0 else "-",
                               feature=feat, beats=len(B), valid=int(valid.sum()),
                               yield_pct=100 * valid.mean(), hr_scg=60 * hr_s,
                               ptt_median_ms=np.median(pv) if len(pv) else np.nan,
                               ptt_iqr_ms=float(np.subtract(*np.percentile(pv, [75, 25]))) if len(pv) > 3 else np.nan,
                               ptt_robust_sd_ms=robust_sd(pv),
                               split_half_ms=float(np.median(pv[:half]) - np.median(pv[half:])) if half >= 5 else np.nan)
                    combos.append(row)
                    store[(meth, band, axis, row["polarity"], feat)] = (ao, valid, extra, s)
    C = pd.DataFrame(combos)
    C.to_csv(os.path.join(outdir, "combos.csv"), index=False)
    hr_scg = C.hr_scg.median()
    ok_t = B.tangent_foot[B.ppg_ok].dropna().to_numpy()
    ao_win = (-CFG["ptt_range"][1], -CFG["ptt_range"][0])
    lines.append("  Heartbeat check (beat-locked ratio: >6 clear, 3-6 weak, <3 none)")
    lines.append("    'before pulse' = only 60-400 ms before the finger pulse, where the AO is searched;")
    lines.append("    the out-of-chest axis (dv = -z) before the pulse is what decisions use")
    verdict = lambda x: "clear" if x > 6 else ("weak" if x > 3 else "none")
    for band in sorted({b for b, _ in S}):
        for axis in ("dv", "pca"):
            sig = S[(band, axis)][:n]
            snr, lock = beat_locked(sig, th[:n], ok_t, fs_hi, win=ao_win)
            _, lock_all = beat_locked(sig, th[:n], ok_t, fs_hi)
            name = "out-of-chest" if axis == "dv" else "best direction"
            lines.append(f"  SCG {band:<9} {name:<15} before pulse {lock:5.1f} ({verdict(lock)}), "
                         f"whole window {lock_all:5.1f} ({verdict(lock_all)})")
            summary[f"scg_lock_{band}_{axis}"] = lock
            summary[f"scg_lockall_{band}_{axis}"] = lock_all
    bands_sorted = sorted({b for b, _ in S}, key=lambda b: float(b.split("-")[0]))
    fixed_band = bands_sorted[min(CFG["fixed_band_index"], len(bands_sorted) - 1)]
    summary["fixed_band"] = fixed_band
    dv_locks = [summary.get(f"scg_lock_{fixed_band}_dv", np.nan)]
    dv_locks = [v for v in dv_locks if np.isfinite(v)]
    any_locks = [v for k, v in summary.items() if k.startswith(("scg_lock_", "scg_lockall_")) and np.isfinite(v)]
    best_lock = max(dv_locks) if dv_locks else np.nan
    any_lock = max(any_locks) if any_locks else np.nan
    summary["scg_lock_used"] = best_lock
    summary["scg_detected"] = bool(best_lock > 3)
    if meta.get("mode") == "table":
        if best_lock > 3:
            lines.append("  WARNING: the finger pulse leaks into the out-of-chest axis inside the AO window.")
            lines.append("  Chest PTT could be contaminated.")
        elif any_lock > 3:
            lines.append("  Note: a small finger-pulse movement shows in another direction or just after the pulse.")
            lines.append("  It falls outside what the chest analysis uses, so chest PTT is not affected.")
        else:
            lines.append("  No finger-pulse leak in any direction.")
    elif not best_lock > 3:
        lines.append("  WARNING: no heartbeat locked to the pulse in the out-of-chest SCG. The averaged method still")
        lines.append("  returns numbers from pure noise, so treat every PTT below as INVALID for this session.")
    # version 2: grade the recording with the fixed method
    if meta.get("mode") == "chest":
        fk = ("ensemble", fixed_band, "dv", "+", "tangent_foot")
        rowf = C[(C.method == "ensemble") & (C.band == fixed_band) & (C.axis == "dv") & (C.polarity == "+") &
                 (C.feature == "tangent_foot")]
        G = grade_recording(best_lock, store.get(fk, (None, None, None, None))[2], rowf.iloc[0] if len(rowf) else None)
        summary.update(grade="Good" if G["good"] else "Weak", grade_reasons="; ".join(G["reasons"]),
                       grade_halves=G["halves"], grade_second=G["second"], grade_ptt=G["ptt"], grade_spread=G["spread"])
        lines += ["", f"GRADE: {'GOOD' if G['good'] else 'WEAK'}  (fixed method: template, {fixed_band}, out-of-chest axis, tangent foot)",
                  f"  PTT {G['ptt']:.1f} ms, spread {G['spread']:.1f} ms, beats {G['beats']}, heartbeat ratio {G['lock']:.1f}, "
                  f"halves match {G['halves']:.2f}, second bump {G['second']:.2f}"]
        for rr in G["reasons"]:
            lines.append(f"  - {rr}")
    good = C[(C.valid >= CFG["min_valid_beats"]) & (C.yield_pct >= 50)].sort_values("ptt_robust_sd_ms")
    summary.update(hr_scg=float(hr_scg))
    lines += ["", "PTT combinations ranked by within-recording spread (lower = more stable)",
              "  method     band       axis pol feature        valid  yield  median  robSD  split-half"]
    for _, r in good.head(10).iterrows():
        lines.append(f"  {r.method:<10} {r.band:<10} {r.axis:<4} {r.polarity:^3} {r.feature:<14} "
                     f"{r.valid:5d}  {r.yield_pct:4.0f}%  {r.ptt_median_ms:6.1f}  {r.ptt_robust_sd_ms:5.1f}  "
                     f"{r.split_half_ms:+6.1f}")
    if good.empty:
        lines.append("  none passed (need >= %d valid beats and >= 50%% yield)" % CFG["min_valid_beats"])
        open(os.path.join(outdir, "summary.txt"), "w").write("\n".join(lines))
        if verbose:
            print("\n".join(lines))
        return summary
    lines += ["", "Caution: choosing the 'best' row from many combinations overfits. Use pilot sessions",
              "to pick ONE combination, write it down, then judge it on new sessions only."]
    best = good.iloc[0]
    summary.update({f"best_{k}": best[k] for k in ["method", "band", "axis", "polarity", "feature",
                                                     "ptt_median_ms", "ptt_robust_sd_ms", "yield_pct"]})
    key = (best.method, best.band, best.axis, best.polarity, best.feature)
    ao, valid, extra, s = store[key]
    out = B.copy()
    out["ao"] = ao
    out["ptt_ms"] = (B[best.feature] - ao) * 1000
    out["valid"] = valid
    out.to_csv(os.path.join(outdir, "beats_best.csv"), index=False)
    # fixed default combination, for comparing sessions fairly
    dflt = C[(C.method == "ensemble") & (C.axis == "dv") & (C.polarity == "+") &
             (C.feature == "tangent_foot") & (C.band == fixed_band)]
    if len(dflt):
        summary["default_ptt_ms"] = float(dflt.ptt_median_ms.iloc[0])
    for _, r in C.iterrows():
        summary[f"ptt|{r.method}|{r.band}|{r.axis}|{r.polarity}|{r.feature}"] = r.ptt_median_ms

    # ---------------- plots
    tt = P["t"][:n] - P["t"][0]
    span = (tt >= 5) & (tt <= 15)
    fig, ax = plt.subplots(3, 1, figsize=(10, 8), sharex=True)
    rt = P["raw_t"] - P["t"][0]
    rs = (rt >= 5) & (rt <= 15)
    ax[0].plot(rt[rs], P["raw_L"][rs], lw=0.8)
    ax[0].set_ylabel(f"light ({P['channel']})")
    ax[1].plot(tt[span], P["v"][:n][span], lw=0.8)
    for _, b in B.iterrows():
        x = b[best.feature] - P["t"][0]
        if 5 <= x <= 15:
            ax[1].axvline(x, color="tab:orange", lw=0.6)
    ax[1].set_ylabel("PPG (volume)")
    ax[2].plot(tt[span], s[span], lw=0.8, color="k")
    for a_, v_ in zip(ao, valid):
        if np.isfinite(a_) and 5 <= a_ - P["t"][0] <= 15:
            ax[2].axvline(a_ - P["t"][0], color="tab:green" if v_ else "tab:red", lw=0.6)
    for _, m in markers.iterrows():
        x = m.t - P["t"][0]
        if 5 <= x <= 15:
            for a in ax:
                a.axvline(x, color="purple", ls="--")
    ax[2].set_ylabel(f"SCG {best.axis}{best.polarity} {best.band}")
    ax[2].set_xlabel("s")
    ax[0].set_title(f"{summary['session']}: AO (green=valid) and PPG {best.feature} (orange)")
    fig.tight_layout(); fig.savefig(os.path.join(outdir, "overview.png"), dpi=110); plt.close(fig)

    ens = store.get(("ensemble", best.band, best.axis, best.polarity, best.feature), (None, None, None, None))[2]
    if ens and ens.get("S") is not None:
        fig, ax = plt.subplots(figsize=(8, 4))
        x = (np.arange(ens["S"].shape[1]) - ens["pre"]) / fs_hi * 1000
        q1, q3 = np.percentile(ens["S"], [25, 75], axis=0)
        ax.fill_between(x, q1, q3, alpha=0.3)
        ax.plot(x, ens["template"], color="k")
        if ens["ao_i"] is not None:
            ax.axvline((ens["ao_i"] - ens["pre"]) / fs_hi * 1000, color="tab:green", label="AO (template)")
        ax.axvline(0, color="tab:orange", label=f"PPG {best.feature}")
        ax.set_xlabel("ms relative to PPG feature"); ax.set_ylabel("SCG")
        ax.legend(); ax.set_title("SCG beats aligned to the finger pulse (median, IQR)")
        fig.tight_layout(); fig.savefig(os.path.join(outdir, "ensemble.png"), dpi=110); plt.close(fig)

    fig, ax = plt.subplots(2, 1, figsize=(9, 5), sharex=True)
    ax[0].plot(out.t_peak[valid] - P["t"][0], out.ptt_ms[valid], ".")
    ax[0].set_ylabel("PTT ms")
    ok = B.ppg_ok
    ax[1].plot(B.t_peak[ok] - P["t"][0], B.pir[ok], ".", color="tab:purple")
    ax[1].set_ylabel("PIR"); ax[1].set_xlabel("s")
    fig.tight_layout(); fig.savefig(os.path.join(outdir, "ptt_pir.png"), dpi=110); plt.close(fig)

    open(os.path.join(outdir, "summary.txt"), "w").write("\n".join(lines))
    if verbose:
        print("\n".join(lines))
    return summary


# ----------------------------------------------------------------------------- across sessions
def cross_session(root, rows):
    D = pd.DataFrame(rows)
    D.to_csv(os.path.join(root, "all_sessions.csv"), index=False)
    lines = [f"{len(D)} sessions"]
    bp = D.dropna(subset=["cuff_dbp"]) if "cuff_dbp" in D else D.iloc[0:0]
    bp = bp[bp["mode"] != "tap"] if len(bp) else bp
    if len(bp) and "scg_detected" in bp:
        bp = bp[bp["scg_detected"] == True]
    if len(bp) < 4:
        lines.append("Need >= 4 sessions with cuff readings (and a spread of BP) to test PTT/PIR vs BP.")
    else:
        res = []
        cols = [c for c in D.columns if c.startswith("ptt|")] + ["pir_median"]
        for target in ["cuff_dbp", "cuff_sbp"]:
            y = bp[target].astype(float).to_numpy()
            for c in cols:
                x = bp[c].astype(float).to_numpy()
                m = np.isfinite(x) & np.isfinite(y) & (x > 0)
                if m.sum() < 4:
                    continue
                X = np.log(x[m]) if c.startswith("ptt|") else 1 / x[m]
                yy = y[m]
                r = np.corrcoef(X, yy)[0, 1]
                loo, base = [], []
                for i in range(len(yy)):
                    tr = np.arange(len(yy)) != i
                    a, b = np.polyfit(X[tr], yy[tr], 1)
                    loo.append(a * X[i] + b - yy[i]); base.append(yy[tr].mean() - yy[i])
                res.append(dict(target=target, predictor=("ln " if c.startswith("ptt|") else "1/") + c, n=int(m.sum()),
                                r=r, loo_rmse=np.sqrt(np.mean(np.square(loo))),
                                mean_baseline_rmse=np.sqrt(np.mean(np.square(base)))))
        R = pd.DataFrame(res)
        R["beats_baseline"] = R.loo_rmse < R.mean_baseline_rmse
        R.sort_values(["target", "loo_rmse"]).to_csv(os.path.join(root, "bp_models.csv"), index=False)
        for tg in ["cuff_dbp", "cuff_sbp"]:
            sub = R[R.target == tg].sort_values("loo_rmse").head(5)
            lines.append(f"\nTop predictors of {tg} (leave-one-out RMSE vs predicting the mean):")
            for _, r in sub.iterrows():
                lines.append(f"  {r.predictor:<60} n={r.n} r={r.r:+.2f} LOO {r.loo_rmse:.1f} vs base "
                             f"{r.mean_baseline_rmse:.1f} mmHg")
        lines.append("\nWith few sessions, many predictors and one person, expect false winners. Confirm on new data.")
    open(os.path.join(root, "cross_session.txt"), "w").write("\n".join(lines))
    print("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--ppg-channel", choices=["r", "g", "b"])
    ap.add_argument("--explore-polarity", action="store_true")
    a = ap.parse_args()
    if a.explore_polarity:
        CFG["polarities"] = (+1, -1)
    if a.all:
        root = a.paths[0]
        sess = sorted(os.path.dirname(p) for p in glob.glob(os.path.join(root, "*", "meta.json")))
        rows = []
        for s in sess:
            print("=" * 70)
            try:
                rows.append(analyze(s, a.ppg_channel))
            except Exception as e:
                print(f"{s}: failed ({e})")
        cross_session(root, rows)
    else:
        for s in a.paths:
            analyze(s, a.ppg_channel)


if __name__ == "__main__":
    main()
