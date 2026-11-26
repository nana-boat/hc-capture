# HC Capture: analysis method, version 2.1

Written 22 November 2026, before any recording made with it. Fixed for the next session: do not change it because
of the next session's recordings. Any change gets a new version number, an entry in the change history below, a
re-analysis of every recording, and is judged on new recordings only.

Research prototype. Not a medical device. No blood pressure is estimated.

## Recording
- Camera: the lens the user picks (the one a fingertip can cover together with the flash), remembered per phone.
- Flash: starts at 70 %. While positioning it is raised in 10 % steps (to 100 %) only if the finger is dim and
  the camera is already at its most sensitive. It is fixed during the recording. The level used is saved
  (`torch_level_record`).
- Finger colour: chosen automatically on the first chest or table recording whose finger pulse passes every
  check, then kept. It is chosen again only after 3 failed recordings in a row, or on purpose.
- Chest placement: phone upright (long side along the breastbone, camera end towards the chin), centred,
  screen against the chest, on skin or a thin top. Main tests: lower breastbone, bottom edge just above the
  bottom tip of the breastbone. Placement test: alternate lower breastbone and diaphragm area (just below
  the tip of the breastbone). Diaphragm area only: the phone may also lie sideways (long side across the body).
  Orientation (`orientation`) and phone angle (`tilt`) at the start are saved; they are reported, not used.
- Start: double tap the phone once the app says it's in place; recording starts 3 s later. (A countdown is
  the backup option.)
- Length: 45 s. At 45 s the app grades the recording; if it isn't Good it carries on to 60 s.

## Analysis (fixed method)
1. Record phase only, 1 s trimmed at both ends.
2. Finger pulse: the saved colour, band-passed 0.5–10 Hz, upsampled to 1000 Hz. Pulse arrival = tangent foot.
   Beats with abnormal size or timing, or saturation, are dropped.
3. Chest signal: accelerometer z axis, band-passed **5–40 Hz**, upsampled to 1000 Hz.
   **Sign: +z = out of the chest.** iOS reports minus the acceleration, so with the screen against the chest
   the out-of-chest movement shows as +z. Version 1 used −z and saw the wave upside down.
4. Heartbeat check: the chest signal averaged around the finger pulses, looked at only 60–400 ms before the
   pulse, compared with averages at random times (beat-locked ratio).
5. Valve opening (AO): beats averaged into one template; AO = the most prominent upward peak with a dip within
   60 ms before it, 60–400 ms before the finger pulse; each beat is then aligned to the template (±40 ms) and
   fine-tuned (±10 ms). The peak time is refined to below 1 ms with a parabola through the peak and its two
   neighbours (2.1).
6. PTT = finger-pulse arrival − AO, per beat, 60–400 ms only. Reported: median and robust spread.

## Finger colour check
Per colour: brightness, clean beats, rhythm clarity, beat timing variation, beat shape, match with the other
colour. Beat timing and beat shape are taken from the pulse **peak** (2.1; version 2 used the lowest point, which
wanders).

## Grade
Good only if all of these hold; otherwise Weak, with the reasons:
- at least 15 valid beats
- heartbeat ratio above 6
- the averaged heartbeat of odd and even beats match (correlation 0.8 or more)
- the valve-opening bump stands out (the next bump is below 75 % of it)
- PTT spread within the recording 10 ms or less
- **(2.1)** the same method with the chest signal band-passed 1–20 Hz gives a PTT within 10 ms (if not, the two
  filters pick different bumps: the two-bump problem is shown instead of hidden)
- **(2.1)** recordings longer than 50 s: the same method on the first 45 s of the record phase (same 1 s trims)
  gives a PTT within 10 ms of the whole recording

The first five thresholds are judgement calls set on the first 6 chest recordings (22 Nov 2026). The two 2.1
limits (10 ms) were set after seeing session 1 and session 2 (see the change history). The 45 s check during
recording uses the 1–20 Hz check too, so a recording where the filters disagree carries on to 60 s.

## Flags (the recording doesn't count)
Finger too dark at the start; the saved colour fails its quality check; the phone not in the turn its site
expects (version 2.2 table below).

## Sites and turns (version 2.2, app 0.4.2)
| Code | Site | Turn |
|---|---|---|
| `sternum` | lower breastbone (reference) | upright |
| `sternum_sideways` | lower breastbone, sideways | sideways |
| `left_clavicle` | below the left collarbone | sideways |
| `manubrium` | top of the breastbone | sideways |
| `right_clavicle` | below the right collarbone | sideways |
| `mid_sternum` | mid-breastbone | upright |
| `diaphragm` | diaphragm area (old test) | upright or sideways |

Upright: gravity y below -0.6 and |x| below 0.5. Sideways: |x| 0.6 or more and |y| below 0.5. The grade never uses
the turn (the chest signal is the out-of-chest axis, z), so nothing else changes. The site test is judged on the
laptop by its own fingerprinted rules (site test rules v1), not by this app.

## Pass marks for the next 5 lower-breastbone recordings (set in advance, unchanged from version 2)
- Good in at least 4 of 5
- PTT spread within each counted recording 10 ms or less
- PTT spread between recordings (SD) 15 ms or less
- no colour or light flags

## What this does not show
Without an ECG or ultrasound we cannot prove the chosen bump is the true valve opening; we can only show it is
picked consistently. Published lab work matches an SCG point to valve opening within about 3 ms on average,
±11 ms between people (Sørensen et al., Sci Rep 2018), with lab sensors, not a hand-held phone. Whether a per-user
or a population calibration is used has not been decided; nothing here depends on it.

## Change history (what was changed after which data)
- **Version 1** (app 0.3.x): chest sign −z, 1–20 Hz and 5–40 Hz explored, best combination ranked by stability.
- **Version 2** (app 0.4.0, written 22 Nov 2026 after session 1, 6 chest recordings): sign changed to +z after
  checking the iOS convention on table recordings; 5–40 Hz chosen as the fixed band after seeing session 1;
  grade thresholds set on session 1. Called "locked", but the colour check was changed after session 2, so it
  was not truly locked.
- **Version 2.1** (app 0.4.1, written 22 Nov 2026 after session 2, 8 chest recordings, and an independent review):
  colour check from the pulse peak (designed after session 2 showed false alarms in 1716, 1718, 1725, 1727);
  sub-millisecond peak time (spread was stuck in 0.74 ms steps); 1–20 Hz agreement check (session 1 showed that
  the band decides which bump is picked: about 196 vs 144 ms); first-45-s agreement check (1723: 136 vs 118 ms);
  diaphragm area sideways allowed; flash level, orientation and tilt saved; "(dv = −z)" label corrected.
  Re-analysis of all 14 old chest recordings with 2.1 (code check only; these recordings set the rules and
  cannot test them): Good 6 of 14 (version 2: 10 of 14). 1538, 1540, 1544 become Weak (filters disagree by about
  52 ms); 1723 becomes Weak (first 45 s 136.3 vs 118.1 ms). PTT medians move by 0.3 ms or less.
  Recordings 1716, 1718 and 1725 pass the 1–20 Hz check by 7–9 ms, close to the 10 ms limit.
- **Version 2.2** (app 0.4.2, written 26 Nov 2026 before any site-test recording): adds the turn table above for
  the site-test sites. The grade, filters, heartbeat check and PTT are unchanged. App 0.4.2 also adds the site
  picker, alternation of any test site with the lower breastbone, a get-ready checklist saved in meta.json
  (information only), and a simpler look. Camera, motion capture and saving code are unchanged from 0.4.1.
