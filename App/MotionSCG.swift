import CoreMotion
import Foundation

/// One 3-axis sample. `t` is CoreMotion timestamp (seconds since boot, host clock base).
struct XYZSample {
    var t: Double
    var x: Double
    var y: Double
    var z: Double
}

/// Raw accelerometer (SCG, in g) and gyroscope (rad/s) at the highest rate the phone allows.
final class MotionSCG {
    private let mm = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private let lock = NSLock()
    private var acc: [XYZSample] = []
    private var gyro: [XYZSample] = []

    var accelerometerAvailable: Bool { mm.isAccelerometerAvailable }

    func start(hz: Double) {
        lock.lock(); acc.removeAll(keepingCapacity: true); gyro.removeAll(keepingCapacity: true); lock.unlock()
        mm.accelerometerUpdateInterval = 1.0 / hz
        mm.gyroUpdateInterval = 1.0 / hz
        mm.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let d = data else { return }
            let s = XYZSample(t: d.timestamp, x: d.acceleration.x, y: d.acceleration.y, z: d.acceleration.z)
            self.lock.lock(); self.acc.append(s); self.lock.unlock()
        }
        if mm.isGyroAvailable {
            mm.startGyroUpdates(to: queue) { [weak self] data, _ in
                guard let self = self, let d = data else { return }
                let s = XYZSample(t: d.timestamp, x: d.rotationRate.x, y: d.rotationRate.y, z: d.rotationRate.z)
                self.lock.lock(); self.gyro.append(s); self.lock.unlock()
            }
        }
    }

    func stop() {
        mm.stopAccelerometerUpdates()
        mm.stopGyroUpdates()
    }

    func takeAll() -> (acc: [XYZSample], gyro: [XYZSample]) {
        lock.lock(); defer { lock.unlock() }
        return (acc, gyro)
    }

    func recentAcc(seconds: Double) -> [XYZSample] {
        lock.lock(); defer { lock.unlock() }
        guard let last = acc.last else { return [] }
        var i = acc.count - 1
        while i > 0 && acc[i - 1].t > last.t - seconds { i -= 1 }
        return Array(acc[i...])
    }
}
