import CoreMedia
import Foundation
import UIKit

struct SummaryRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let ok: Bool?
}

enum HostClock {
    /// Same time base as camera frames (converted) and CoreMotion timestamps.
    static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
}

enum SessionStore {
    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func list() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func newFolder(mode: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let url = root.appendingPathComponent("\(f.string(from: Date()))_\(mode)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var modelIdentifier: String {
        var s = utsname()
        uname(&s)
        return withUnsafePointer(to: &s.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static func write(folder: URL, ppg: [PPGSample], acc: [XYZSample], gyro: [XYZSample],
                      markers: [(Double, String)], tRecord: Double, tEnd: Double, meta: [String: Any]) throws {
        func phase(_ t: Double) -> String { t < tRecord ? "settle" : "record" }

        var s = "t,r,g,b,sat_r,sat_any,iso,exp_ms,phase\n"
        s.reserveCapacity(ppg.count * 72)
        for p in ppg where p.t <= tEnd {
            s += String(format: "%.6f,%.3f,%.3f,%.3f,%.4f,%.4f,%.1f,%.4f,", p.t, p.r, p.g, p.b, p.satR, p.satAny, p.iso, p.expMs)
            s += phase(p.t) + "\n"
        }
        try s.write(to: folder.appendingPathComponent("ppg.csv"), atomically: true, encoding: .utf8)

        func xyz(_ rows: [XYZSample], _ name: String) throws {
            var o = "t,x,y,z,phase\n"
            o.reserveCapacity(rows.count * 60)
            for r in rows where r.t <= tEnd {
                o += String(format: "%.6f,%.6f,%.6f,%.6f,", r.t, r.x, r.y, r.z) + phase(r.t) + "\n"
            }
            try o.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try xyz(acc, "acc.csv")
        try xyz(gyro, "gyro.csv")

        var m = "t,label\n"
        for (t, l) in markers { m += String(format: "%.6f,", t) + l + "\n" }
        try m.write(to: folder.appendingPathComponent("markers.csv"), atomically: true, encoding: .utf8)

        try writeMeta(folder: folder, meta: meta)
    }

    static func writeMeta(folder: URL, meta: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("meta.json"))
    }

    static func readMeta(folder: URL) -> [String: Any] {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }

    /// Zip a folder using the system (no third-party code).
    static func zip(_ dir: URL) throws -> URL {
        var coordError: NSError?
        var result: URL?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: [.forUploading], error: &coordError) { zipURL in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(dir.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: zipURL, to: dest)
                result = dest
            } catch {
                copyError = error
            }
        }
        if let e = coordError { throw e }
        if let e = copyError { throw e }
        guard let r = result else { throw CocoaError(.fileWriteUnknown) }
        return r
    }

    // MARK: quick on-phone quality check (the real analysis runs in hc_analyze.py)

    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return .nan }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : 0.5 * (s[s.count / 2 - 1] + s[s.count / 2])
    }

    static func pulsatility(_ x: [Double], fs: Double) -> Double {
        let w = max(3, Int(fs))
        guard x.count > 3 * w else { return .nan }
        var resid: [Double] = []
        var run = x[0..<w].reduce(0, +)
        for i in w..<x.count {
            run += x[i] - x[i - w]
            resid.append(x[i - w / 2] - run / Double(w))
        }
        let mean = x.reduce(0, +) / Double(x.count)
        let m = resid.reduce(0, +) / Double(resid.count)
        let sd = sqrt(resid.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(resid.count))
        return mean > 0 ? 100 * sd / mean : .nan
    }

    static func summarize(ppg: [PPGSample], acc: [XYZSample], dropped: Int, targetFPS: Double,
                          tRecord: Double, tEnd: Double) -> [SummaryRow] {
        let rec = ppg.filter { $0.t >= tRecord && $0.t <= tEnd }
        let ra = acc.filter { $0.t >= tRecord && $0.t <= tEnd }
        var rows: [SummaryRow] = []
        guard rec.count > 10, ra.count > 10 else {
            return [SummaryRow(label: "Data", value: "too little data recorded", ok: false)]
        }
        let dts = zip(rec.dropFirst(), rec).map { $0.t - $1.t }
        let md = median(dts)
        let fps = 1 / md
        let gaps = dts.filter { $0 > 1.5 * md }.count
        rows.append(SummaryRow(label: "Camera rate", value: String(format: "%.1f fps (target %.0f)", fps, targetFPS),
                               ok: fps >= 0.9 * targetFPS))
        rows.append(SummaryRow(label: "Frame gaps / drops", value: "\(gaps) / \(dropped)", ok: gaps < 5))
        let adt = median(zip(ra.dropFirst(), ra).map { $0.t - $1.t })
        rows.append(SummaryRow(label: "Accelerometer rate", value: String(format: "%.1f Hz", 1 / adt), ok: 1 / adt >= 90))
        let n = Double(rec.count)
        let mr = rec.map { Double($0.r) }.reduce(0, +) / n
        let mg = rec.map { Double($0.g) }.reduce(0, +) / n
        let mb = rec.map { Double($0.b) }.reduce(0, +) / n
        rows.append(SummaryRow(label: "Colour levels R/G/B", value: String(format: "%.0f / %.0f / %.0f", mr, mg, mb),
                               ok: mr < 245 && mg > 5))
        let sat = 100 * rec.map { Double($0.satAny) }.reduce(0, +) / n
        rows.append(SummaryRow(label: "Saturated pixels", value: String(format: "%.1f%%", sat), ok: sat < 2))
        let pg = pulsatility(rec.map { Double($0.g) }, fs: fps)
        let pr = pulsatility(rec.map { Double($0.r) }, fs: fps)
        rows.append(SummaryRow(label: "Pulse strength G / R", value: String(format: "%.2f%% / %.2f%%", pg, pr),
                               ok: max(pg, pr) > 0.2))
        let isos = rec.map { $0.iso }
        let held = (isos.max() ?? 0) - (isos.min() ?? 0) < 1
        rows.append(SummaryRow(label: "Exposure held fixed", value: held ? "yes" : "no (changed during recording)", ok: held))
        rows.append(SummaryRow(label: "Recorded", value: String(format: "%.0f s", tEnd - tRecord), ok: nil))
        return rows
    }
}
