# HC Capture: locked analysis method, version 2

Locked on 22 November 2026, before the version 2 test recordings. Do not change it because of those
recordings. Any change gets a new version number, a note here, a re-analysis of every recording,
and is judged on new recordings only.

Research prototype. Not a medical device. No blood pressure is estimated.

## Recording
- Camera: the lens the user picks (the one a fingertip can cover together with the flash), remembered per phone.
- Flash: starts at 70 %. While positioning it is raised in 10 % steps (to 100 %) only if the finger is dim and
  the camera is already at its most sensitive. It is fixed during the recording.
- Finger colour: chosen automatically on the first chest or table recording whose finger pulse passes every
  check, then kept. It is chosen again only after 3 failed recordings in a row, or on purpose.
- Chest placement: phone upright (long side along the breastbone, camera end towards the chin), centred,
  screen against the chest, on skin or a thin top. Main tests: lower breastbone, bottom edge just above the
  bottom tip of the breastbone. Placement test: alternate lower breastbone and diaphragm area (just below
  the tip of the breastbone).
- Start: double tap the phone once the app says it's in place; recording starts 3 s later. (A countdown is
  the backup option.)
- Length: 45 s. At 45 s the app grades the recording; if it isn't Good it carries on to 60 s.

## Analysis (fixed method)
1. Record phase only, 1 s trimmed at both ends.
2. Finger pulse: the saved colour, band-passed 0.5–10 Hz, upsampled to 1000 Hz. Pulse arrival = tangent foot.
   Beats with abnormal size or timing, or saturation, are dropped.
3. Chest signal: accelerometer z axis, band-passed **5–40 Hz**, upsampled to 1000 Hz.
   **Sign: +z = out of the chest.** iOS reports minus the acceleration, so with the screen against the chest
   the out-of-chest movement shows as +z. Version 1 used −z and saw the wave upside down; that caused the
   two-similar-bumps problem.
4. Heartbeat check: the chest signal averaged around the finger pulses, looked at only 60–400 ms before the
   pulse, compared with averages at random times (beat-locked ratio).
5. Valve opening (AO): beats averaged into one template; AO = the most prominent upward peak with a dip within
   60 ms before it, 60–400 ms before the finger pulse; each beat is then aligned to the template (±40 ms) and
   fine-tuned (±10 ms).
6. PTT = finger-pulse arrival − AO, per beat, 60–400 ms only. Reported: median and robust spread.

## Grade
Good only if all of these hold; otherwise Weak, with the reasons:
- at least 15 valid beats
- heartbeat ratio above 6
- the averaged heartbeat of odd and even beats match (correlation 0.8 or more)
- the valve-opening bump stands out (the next bump is below 75 % of it)
- PTT spread within the recording 10 ms or less

These thresholds are judgement calls, set on the first 6 chest recordings (22 Nov 2026).

## Flags (the recording doesn't count)
Finger too dark at the start; the saved colour fails its quality check; the phone not upright.

## Pass marks for the 5 test recordings (set in advance)
- Good in at least 4 of 5
- PTT spread within each counted recording 10 ms or less
- PTT spread between recordings (SD) 15 ms or less
- no colour or light flags

## What this does not show
Without an ECG or ultrasound we cannot prove the chosen bump is the true valve opening; we can only show it is
picked consistently. Published lab work matches an SCG point to valve opening within about 3 ms on average,
±11 ms between people (Sørensen et al., Sci Rep 2018), with lab sensors, not a hand-held phone.
