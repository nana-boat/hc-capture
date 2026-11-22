import AVFoundation
import UIKit

/// One camera frame reduced to colour means. `t` is host-clock seconds (same base as CoreMotion timestamps).
struct PPGSample {
    var t: Double
    var r: Float
    var g: Float
    var b: Float
    var satR: Float      // fraction of sampled pixels with red >= 250
    var satAny: Float    // fraction with any channel >= 250
    var iso: Float
    var expMs: Float
}

struct FormatPick {
    let format: AVCaptureDevice.Format
    let fps: Double
    let frameDuration: CMTime
    let width: Int
    let height: Int
}

/// Which rear lens records the fingertip. The flash sits in a different spot from each lens,
/// so the best lens is the one a fingertip can cover together with the flash.
enum CameraLens: String, CaseIterable, Identifiable {
    case main, ultraWide, telephoto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .main: return "Main (1x)"
        case .ultraWide: return "Ultra-wide (0.5x)"
        case .telephoto: return "Telephoto"
        }
    }
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .main: return .builtInWideAngleCamera
        case .ultraWide: return .builtInUltraWideCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
}

enum CaptureError: LocalizedError {
    case noCamera, cannotAddInput, cannotAddOutput, noFormat
    case noLens(String)
    var errorDescription: String? {
        switch self {
        case .noLens(let n): return "This phone has no \(n) camera."
        case .noCamera: return "No rear camera found."
        case .cannotAddInput: return "Could not open the camera."
        case .cannotAddOutput: return "Could not read camera frames."
        case .noFormat: return "No suitable camera format."
        }
    }
}

/// Rear camera + torch fingertip PPG with fixed (locked) camera settings and per-frame timestamps.
final class CameraPPG: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "hc.camera.session")
    private let videoQueue = DispatchQueue(label: "hc.camera.video", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var torchDevice: AVCaptureDevice?
    private var configured = false
    private var customExposure = false
    private var maxDur: Double = 1.0 / 60.0
    private var torchLevel: Float = 1.0

    private let lock = NSLock()
    private var samples: [PPGSample] = []
    private var dropped = 0

    // touched only on videoQueue
    private var adaptive = false
    private var frameCount = 0

    // MARK: configuration

    func configure(targetFPS: Double, lens: CameraLens, torchLevel level: Double) throws -> [String: Any] {
        torchLevel = Float(min(max(level, 0.1), 1.0))
        guard let dev = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) else {
            throw CaptureError.noLens(lens.title)
        }
        let currentID = session.inputs.compactMap { ($0 as? AVCaptureDeviceInput)?.device.uniqueID }.first
        let switching = configured && currentID != dev.uniqueID
        device = dev
        // if this lens has no torch of its own, light the finger with the main camera's torch
        torchDevice = dev.hasTorch ? dev : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if switching {
            for i in session.inputs { session.removeInput(i) }
            let input = try AVCaptureDeviceInput(device: dev)
            guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
            session.addInput(input)
        }
        if !configured {
            let input = try AVCaptureDeviceInput(device: dev)
            guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
            session.addInput(input)
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
            session.addOutput(output)
            configured = true
        }
        if let c = output.connection(with: .video), c.isVideoStabilizationSupported {
            c.preferredVideoStabilizationMode = .off
        }

        guard let pick = CameraPPG.pickFormat(dev, target: targetFPS) else { throw CaptureError.noFormat }
        try dev.lockForConfiguration()
        defer { dev.unlockForConfiguration() }
        dev.activeFormat = pick.format
        dev.activeVideoMinFrameDuration = pick.frameDuration
        dev.activeVideoMaxFrameDuration = pick.frameDuration

        let f = dev.activeFormat
        var hdrOff = false
        if f.isVideoHDRSupported {
            dev.automaticallyAdjustsVideoHDREnabled = false
            dev.isVideoHDREnabled = false
            hdrOff = true
        }
        if dev.isLowLightBoostSupported {
            dev.automaticallyEnablesLowLightBoostWhenAvailable = false
        }
        var focus = "unlocked"
        if dev.isLockingFocusWithCustomLensPositionSupported {
            dev.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil)
            focus = "locked lens 1.0"
        } else if dev.isFocusModeSupported(.locked) {
            dev.focusMode = .locked
            focus = "locked"
        }
        var wb = "auto"
        if dev.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
            dev.setWhiteBalanceModeLocked(with: AVCaptureDevice.WhiteBalanceGains(redGain: 1, greenGain: 1, blueGain: 1),
                                          completionHandler: nil)
            wb = "locked gains 1,1,1"
        } else if dev.isWhiteBalanceModeSupported(.locked) {
            dev.whiteBalanceMode = .locked
            wb = "locked (current)"
        }
        let minDur = CMTimeGetSeconds(f.minExposureDuration)
        maxDur = max(minDur, min(CMTimeGetSeconds(pick.frameDuration) * 0.9, CMTimeGetSeconds(f.maxExposureDuration)))
        customExposure = dev.isExposureModeSupported(.custom)
        let torchName: String = torchDevice?.localizedName ?? "none"
        let lensName: String = dev.localizedName
        let lensKey: String = lens.rawValue
        let torchLevelValue: Double = Double(torchLevel)

        return [
            "width": pick.width, "height": pick.height,
            "fps_selected": pick.fps,
            "frame_duration_s": CMTimeGetSeconds(pick.frameDuration),
            "iso_range": [f.minISO, f.maxISO],
            "exposure_range_ms": [minDur * 1000, CMTimeGetSeconds(f.maxExposureDuration) * 1000],
            "exposure_control": customExposure ? "custom, adapted during settle then frozen" : "auto during settle then locked",
            "white_balance": wb, "focus": focus, "hdr_disabled": hdrOff,
            "stabilization": "off", "pixel_format": "BGRA",
            "roi": "central 60% of frame, every 8th pixel in x and y",
            "torch": dev.hasTorch,
            "lens": lensKey,
            "lens_name": lensName,
            "torch_device": torchName,
            "torch_level": torchLevelValue,
        ]
    }

    /// Highest frame rate up to the target, then the smallest frame size (>= 640 px wide).
    static func pickFormat(_ dev: AVCaptureDevice, target: Double) -> FormatPick? {
        var best: FormatPick?
        for f in dev.formats {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            if d.width < 640 { continue }
            guard let range = f.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) else { continue }
            let fps = min(range.maxFrameRate, target)
            if fps < range.minFrameRate { continue }
            let dur = fps >= range.maxFrameRate - 0.01
                ? range.minFrameDuration
                : CMTime(value: 1, timescale: CMTimeScale(fps.rounded()))
            let cand = FormatPick(format: f, fps: fps, frameDuration: dur, width: Int(d.width), height: Int(d.height))
            if let b = best {
                if fps > b.fps + 0.5 || (abs(fps - b.fps) <= 0.5 && cand.width * cand.height < b.width * b.height) {
                    best = cand
                }
            } else {
                best = cand
            }
        }
        return best
    }

    // MARK: run

    func start() async {
        lock.lock(); samples.removeAll(keepingCapacity: true); dropped = 0; lock.unlock()
        videoQueue.sync { self.adaptive = true; self.frameCount = 0 }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.startRunning()
                self.primeDevice()
                c.resume()
            }
        }
    }

    private func primeDevice() {
        guard let dev = device else { return }
        do { try dev.lockForConfiguration() } catch { return }
        defer { dev.unlockForConfiguration() }
        if let td = torchDevice, td.hasTorch, td.isTorchModeSupported(.on) {
            if td.uniqueID == dev.uniqueID {
                do { try dev.setTorchModeOn(level: min(torchLevel, AVCaptureDevice.maxAvailableTorchLevel)) } catch { dev.torchMode = .on }
            } else if (try? td.lockForConfiguration()) != nil {
                do { try td.setTorchModeOn(level: min(torchLevel, AVCaptureDevice.maxAvailableTorchLevel)) } catch { td.torchMode = .on }
                td.unlockForConfiguration()
            }
        }
        let f = dev.activeFormat
        if customExposure {
            dev.setExposureModeCustom(duration: CMTime(seconds: maxDur, preferredTimescale: 1_000_000),
                                      iso: f.minISO, completionHandler: nil)
        } else if dev.isExposureModeSupported(.continuousAutoExposure) {
            dev.exposureMode = .continuousAutoExposure
        }
    }

    /// Stop adapting exposure; from here on camera settings stay fixed.
    func freezeExposure() {
        videoQueue.sync { self.adaptive = false }
        guard let dev = device, !customExposure else { return }
        if (try? dev.lockForConfiguration()) != nil {
            if dev.isExposureModeSupported(.locked) { dev.exposureMode = .locked }
            dev.unlockForConfiguration()
        }
    }

    func stop() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if let td = self.torchDevice, td.hasTorch, (try? td.lockForConfiguration()) != nil {
                    td.torchMode = .off
                    td.unlockForConfiguration()
                }
                self.session.stopRunning()
                c.resume()
            }
        }
    }

    func takeAll() -> ([PPGSample], Int) {
        lock.lock(); defer { lock.unlock() }
        return (samples, dropped)
    }

    func recent(seconds: Double) -> [PPGSample] {
        lock.lock(); defer { lock.unlock() }
        guard let last = samples.last else { return [] }
        var i = samples.count - 1
        while i > 0 && samples[i - 1].t > last.t - seconds { i -= 1 }
        return Array(samples[i...])
    }

    // MARK: frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let t: Double
        if let clk = session.synchronizationClock {
            t = CMSyncConvertTime(pts, from: clk, to: CMClockGetHostTimeClock()).seconds
        } else {
            t = pts.seconds
        }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let p = base.assumingMemoryBound(to: UInt8.self)

        var sumR = 0, sumG = 0, sumB = 0, n = 0, satR = 0, satAny = 0
        let step = 8
        var y = h / 5
        while y < h - h / 5 {
            let row = p + y * bpr
            var x = w / 5
            while x < w - w / 5 {
                let px = row + x * 4          // BGRA
                let b = Int(px[0]), g = Int(px[1]), r = Int(px[2])
                sumR += r; sumG += g; sumB += b
                if r >= 250 { satR += 1 }
                if r >= 250 || g >= 250 || b >= 250 { satAny += 1 }
                n += 1
                x += step
            }
            y += step
        }
        guard n > 0 else { return }
        let fn = Float(n)
        let mr = Float(sumR) / fn, mg = Float(sumG) / fn, mb = Float(sumB) / fn
        let sAny = Float(satAny) / fn
        var iso: Float = 0
        var expMs: Float = 0
        if let dev = device {
            iso = dev.iso
            expMs = Float(CMTimeGetSeconds(dev.exposureDuration) * 1000)
        }
        let s = PPGSample(t: t, r: mr, g: mg, b: mb, satR: Float(satR) / fn, satAny: sAny, iso: iso, expMs: expMs)
        lock.lock(); samples.append(s); lock.unlock()

        if adaptive {
            frameCount += 1
            if frameCount % 8 == 0 { adjustExposure(hi: max(mr, max(mg, mb)), sat: sAny) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock(); dropped += 1; lock.unlock()
    }

    /// Simple settle-phase controller: keep the brightest channel between 150 and 235 without saturation.
    private func adjustExposure(hi: Float, sat: Float) {
        guard customExposure, let dev = device else { return }
        let f = dev.activeFormat
        var iso = dev.iso
        var dur = CMTimeGetSeconds(dev.exposureDuration)
        let minDur = CMTimeGetSeconds(f.minExposureDuration)
        if sat > 0.01 || hi > 235 {
            if iso > f.minISO * 1.01 { iso = max(f.minISO, iso * 0.8) } else { dur = max(minDur, dur * 0.8) }
        } else if hi < 150 {
            if dur < maxDur * 0.99 { dur = min(maxDur, dur * 1.25) } else { iso = min(f.maxISO, iso * 1.25) }
        } else {
            return
        }
        iso = min(max(iso, f.minISO), f.maxISO)
        dur = min(max(dur, minDur), maxDur)
        do { try dev.lockForConfiguration() } catch { return }
        dev.setExposureModeCustom(duration: CMTime(seconds: dur, preferredTimescale: 1_000_000), iso: iso, completionHandler: nil)
        dev.unlockForConfiguration()
    }
}
