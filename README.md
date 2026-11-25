# HC Capture: HyperChat 3.0 signal feasibility kit

HC Capture is an iPhone app that records two signals at the same time, using only the phone:

- **SCG** (seismocardiogram): the small movements of the chest caused by each heartbeat, read from the phone's accelerometer and gyroscope while the phone rests against the chest.
- **PPG** (photoplethysmogram): the pulse in a fingertip, read from the rear camera and flash while a finger covers the lens.

From the two signals it measures **pulse transit time (PTT)**: the time from the heart's aortic valve opening (seen in the chest signal) to the pulse arriving at the fingertip (seen in the camera signal).

The long-term idea behind HyperChat is to see whether this time can be measured well enough, with an ordinary phone, to one day follow blood pressure without a cuff. This project is the first step: **can the phone capture both signals on one clock and measure PTT repeatably?**

**RESEARCH PROTOTYPE. Not a medical device.** The app shows no blood pressure, and nothing here estimates it. Whether a per-person or a population calibration will ever be used has not been decided, and nothing in the app depends on it.

## Where the work is now (25 Nov 2026)

- **App:** version 0.4.1. It records camera, accelerometer and gyroscope together on one clock: camera about 120 frames per second, motion sensors about 99.5 readings per second.
- **Analysis method:** version 2.1. It finds the heartbeat bump in the chest signal and the foot of the finger pulse, averages over many beats, and gives a PTT with a grade (Good or Weak) for each recording.
- **Current test:** a set of pick checks (rules v4.1) was written, fingerprinted and fixed before any new recording was made. They are being judged once, on new recordings from two sessions on different days: one rested and one after activity. The first session is recorded.
- **Next steps:** testing other chest placements, a second tester (a woman), and later a cuff step to compare PTT with blood pressure.
- **Who has been tested:** one person (the author) so far.

## What the app records

| File | Contents |
|---|---|
| `ppg.csv` | per camera frame: host-clock time, mean R/G/B, saturated-pixel fraction, ISO, exposure, phase (`settle` or `record`) |
| `acc.csv` | accelerometer x/y/z in g, same clock as the camera, phase |
| `gyro.csv` | gyroscope x/y/z in rad/s, same clock, phase |
| `markers.csv` | times the user pressed **Mark** |
| `meta.json` | device, app and analysis version, lens, flash level, phone orientation and tilt, flags, the app's own 45 s grade, cuff blood pressure and notes if entered |

No video is stored. Only `record` rows are analysed.

## Modes

- **Chest + finger:** the main mode. Phone against the chest, fingertip on the camera. Placement: lower breastbone (main) or diaphragm area (test).
- **Table control:** phone lying screen-down on a table with a finger on the camera. It checks whether the finger pulse leaks into the accelerometer. It should show no heartbeat.
- **Tap sync test:** taps on the camera, to check that camera and accelerometer timestamps agree.
- **Phone test:** checks whether the phone gives motion data faster than about 100 readings per second.

## PAT and PTT

- **PAT** (pulse arrival time) starts at the ECG R-wave. A phone has no ECG, so it cannot measure PAT.
- **PTT** here runs from the chest valve-opening bump (SCG) to the finger pulse foot (PPG). It avoids the pre-ejection delay that is built into PAT.

## What is in this repository

```
├── App/                      Swift source (native iOS, SwiftUI)
│   ├── HCCaptureApp.swift    screens
│   ├── Recorder.swift        recording flow, metadata
│   ├── CameraPPG.swift       rear camera and flash, locked settings, per-frame timestamps
│   ├── MotionSCG.swift       accelerometer and gyroscope
│   ├── SessionStore.swift    saving CSV/JSON, zip sharing
│   ├── Analyzer.swift        on-phone analysis (port of analysis/hc_analyze.py)
│   ├── AnalysisViews.swift   result screens and charts
│   ├── DSP.swift, LiveDSP.swift   filters, peaks, live waveform
│   ├── Profile.swift         saved finger colour
│   └── FastSensorTest.swift  the phone test
├── Config/Info.plist
├── project.yml               XcodeGen project
├── codemagic.yaml            Codemagic build
├── .github/workflows/        GitHub Actions build (unsigned IPA)
├── METHOD.md                 the analysis method, grade, pass marks, change history
└── analysis/hc_analyze.py    laptop analysis, same method as the app
```

For the analysis method and its change history, see `METHOD.md`.
