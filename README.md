# HC Capture: HyperChat 3.0 signal feasibility kit

Answers one question first: **can an iPhone capture usable chest SCG and fingertip PPG at the same time, and do the PTT and PIR measurements hold up?**

RESEARCH PROTOTYPE. Not a medical device. The app shows no blood pressure.

```
HyperChatCapture/
├── App/                    Swift source (native iOS, SwiftUI, no React)
│   ├── HCCaptureApp.swift  screens
│   ├── Recorder.swift      recording flow, voice cues, metadata
│   ├── CameraPPG.swift     rear camera + torch, locked settings, per-frame timestamps
│   ├── MotionSCG.swift     accelerometer + gyroscope at max rate
│   └── SessionStore.swift  CSV/JSON saving, zip sharing, on-phone signal check
├── Config/Info.plist
├── project.yml             XcodeGen project (the .xcodeproj is generated in the cloud)
├── codemagic.yaml          Codemagic build
├── .github/workflows/      the same build on GitHub Actions (free option)
└── analysis/hc_analyze.py  laptop analysis: AO, PTT, PIR, sync test, BP comparison
```

## What the app records

| File | Contents |
|---|---|
| `ppg.csv` | per frame: host-clock time, mean R/G/B, saturated-pixel fraction, ISO, exposure |
| `acc.csv` | accelerometer x/y/z in g, CoreMotion timestamps (same clock as the camera) |
| `gyro.csv` | gyroscope (tremor/motion checks) |
| `markers.csv` | times you pressed **Mark** |
| `meta.json` | device, frame rate, camera locks, record start/end, cuff BP you enter, notes |

Camera: rear wide camera, torch on, highest frame rate up to your choice (60/120/240), HDR, stabilisation and low-light boost off, focus and white balance locked (fixed gains). Exposure adapts for 7 s while you get into position, then it's frozen for the whole recording. No video is stored.

## 1. Build the app (Windows + iPhone, free)

You need a GitHub account (free) and an Apple ID.

1. Make a new **GitHub repository** and upload the contents of this folder (`App`, `Config`, `project.yml`, `codemagic.yaml`, `.github`, `analysis`). The GitHub web page's "upload files" works from Windows.
2. Pick one build service:
   - **Codemagic**: sign in with GitHub, add the repo, choose "codemagic.yaml", start the `ios-unsigned` workflow, download `HCCapture-unsigned.ipa` from the build's artifacts.
   - **GitHub Actions**: open the repo's **Actions** tab, choose "Build unsigned IPA", then **Run workflow**. Download the `HCCapture-unsigned-ipa` artifact (it's a zip with the .ipa inside).
3. Install on the iPhone with **Sideloadly** (Windows):
   - Install Sideloadly, plus iTunes and iCloud from Apple's website (not the Microsoft Store versions).
   - Plug in the iPhone, drag the .ipa into Sideloadly, enter your Apple ID, click Start.
   - On the iPhone: Settings > General > VPN & Device Management > trust your Apple ID. iOS 16+ also needs Settings > Privacy & Security > Developer Mode on (restart).
   - With a free Apple ID the app stops opening after 7 days. Re-sideload it to renew. Your recordings stay on the phone.

If a build fails, copy the red error lines from the build log and send them to me.

## 2. Recording plan for the feasibility test

Do these in order. Each test answers one question.

| # | Mode | Repeats | Question |
|---|---|---|---|
| 1 | Tap sync test | 3 | Do camera and accelerometer timestamps stay aligned, and is the offset stable? |
| 2 | Table control | 2 | Does the finger's own pulse leak into the accelerometer? (Should show no heartbeat.) |
| 3 | Chest + finger, at rest | 5 | Is a heartbeat visible in the SCG? How stable is PTT within a recording and between repeats? Which PPG colour works? |
| 4 | Chest + finger, BP changes | 6+ | Do PTT and PIR move with cuff BP? Record at rest, after 2 min handgrip, after light exercise, lying vs sitting. Take a cuff reading straight after each recording and type it in. |

Chest protocol: seated, leaning back slightly, **screen against the chest** on the lower sternum, rear camera facing out, index fingertip lightly covering the camera and flash. No talking, normal breathing. You hear "place the phone", then a vibration when recording starts, and "done" at the end. (There's no sound during recording, because the speaker would shake the accelerometer.)

Use 120 fps unless the on-phone check shows dropped frames.

## 3. Analyse on your laptop

Install Python 3 from python.org, then in a terminal:

```
pip install numpy pandas matplotlib
python analysis/hc_analyze.py --all path\to\Recordings
```

Get the recordings off the phone with **Share all recordings (zip)** in the app (email, Drive, AirDrop to a friend's Mac, etc.), or via the Files app. Unzip them first.

For each session you get `analysis/summary.txt` and charts:

- **Capture quality**: real camera and accelerometer rates, timing jitter, gaps, whether exposure stayed fixed.
- **PPG channels**: which colour has the clearest pulse, and PIR with its beat-to-beat variation.
- **SCG beat-locked ratio**: is there a heartbeat in the accelerometer that is locked to the finger pulse? Above 6 is clear, 3–6 weak, under 3 none. *If it's under 3, PTT for that session is invalid.* The table control should be about 1.
- **PTT table**: three AO methods (Seismo-style rule, beat-averaged template, SCG-first), two filter bands, two axes, and three PPG features (APG peak, tangent foot, max slope). Ranked by within-recording stability.
- **Tap sync**: median offset and spread.
- `--all` also writes `cross_session.txt`: for sessions with cuff readings, how well ln(PTT) or 1/PIR predicts DBP and SBP, using leave-one-out error compared with just predicting the average BP.

### How the analysis was checked
I tested it on simulated recordings where the true AO and pulse times were known:

- tangent-foot timing: about −10 ms bias with 7 ms spread
- beat-averaged AO: about 0 ms bias with 3–7 ms spread (about 10–14 ms at 60 fps)
- Seismo-style per-beat rule: unreliable once noise is realistic

It also confirmed two traps:

- a flipped SCG sign shifts AO by about 30 ms but looks just as "stable", so the sign is fixed by the placement protocol
- the averaged method returns numbers even from pure noise, which is why the beat-locked check exists

Simulations are idealised, so real recordings decide what works.

### Don't fool yourself
Many method combinations plus few sessions means some combination will look good by chance. Use your first sessions to choose **one** combination, write it down, then judge it only on new sessions.

## PAT vs PTT

- **PAT** (pulse arrival time) starts at the ECG R-wave. A phone has no ECG, so it can't measure PAT.
- **PTT** here runs from aortic valve opening (AO, from the SCG) to the finger pulse. This is what the app measures, and it avoids the pre-ejection delay that's built into PAT.
- To compare against PAT you'd need an ECG with a shared clock, e.g. an AD8232 module on a microcontroller. That's a later add-on.

## Known limits

- iPhone accelerometer rate is usually capped near 100 Hz (10 ms steps). The analysis interpolates for finer timing, but real precision has to be measured.
- Camera and CoreMotion timestamps should share the host clock. The tap test checks this on your phone.
- iOS still applies some tone mapping, so PIR from a camera isn't perfectly linear. Compare PIR only between sessions with similar ISO/exposure, and check its test–retest stability first.
