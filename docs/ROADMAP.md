# KOSMOS 3D: roadmap

Review of `main` at `3332414` (28 Oct 2026), tested on a Xiaomi 25078PC3EE (Android 16) with two GoPro HERO13 Black on 30 Oct 2026. Priorities: **P0** blocks real use or store release, **P1** makes the app clearly better, **P2** makes it outstanding.

## 1. What "Smart Capture AI" actually is

The project toggle (now labelled *Capture guidance*) runs a few rules on the phone's compass and GPS: largest heading gap, angle to the previous shot, walking speed. It shows a hint and nothing else. There is no AI and no image analysis. Options:

- **Keep and rename** to *Coverage hints* (done in the text), or
- **Replace** with real image-based checks (blur, exposure, overlap) as described in P1 below. That would earn the name.

## 2. Remove or merge

- **Two upload settings sections** (Storage server and KOSMOS receiver, each with its own auto-upload switch). Merge into one *Upload destination* list with a single auto-upload choice.
- **`app_translations.dart` + `ui_dictionary.dart` + `ui_dictionary_v2.dart`**: three translation mechanisms. Move to Flutter `gen_l10n` ARB files before adding a third language.
- **Hard-coded dark colours**: fixed in project flow, gallery, export, settings. Capture screen, coverage viewer and live monitor are intentionally dark.

## 3. Roadmap

### P0: needed before store release

1. **Phone-hotspot download from all cameras at once (HERO12/13 COHN).** Over BLE: scan networks (`0x02/0x02`), connect camera to the phone hotspot (`0x02/0x05`), create and fetch the COHN certificate (`0xF1/0x67`, `0x6E`), read IP/username/password (`0x6F`). Then HTTPS to every camera in parallel, pinned to its certificate. HERO11 and older keep the sequential camera-Wi-Fi route. This is the biggest usability win for multi-camera rigs.
2. **Background uploads and imports.** Android foreground service / WorkManager, iOS background `URLSession`. Persistent job list that survives the app being closed; multipart upload for files above 5 GB.
3. **Store metadata.** Android release signing and GitHub releases are done (3 Nov). Still open: Play App Signing, Play App Signing, iOS distribution certificate, privacy manifest (`PrivacyInfo.xcprivacy`), data-safety form, app-store screenshots, final bundle ID (e.g. `institute.kreativ.kosmos3d`).
4. **Permissions flow.** One onboarding screen that explains and requests Bluetooth, location, local network, photos. Today permissions pop up mid-task.
5. **Physical acceptance matrix.** HERO9â€“13 single and mixed, low battery, full card, disconnect at each step, 500-shot sessions, app in background. Record results in the repo.
6. ~~**Known cameras.**~~ Done 2 Nov (remembered, wake by tap, Connect all). Still open: rig position per camera.
7. ~~**Project-scoped import.**~~ Done 2 Nov via the capture-time windows of the shutter log.
7a. **Hardware checks still open:** *Erase all files* was verified on two HERO13s (3 Nov). *Power off* still needs a run with a hand on the camera.

### P1: makes it clearly better

8. **Rig presets per camera model.** Save the full settings table from *All camera settings* as a named rig profile and apply it in one tap. Export/import as QR or file for a second phone.
9. **Exposure check after the first shot.** Download one thumbnail per camera (`/gopro/media/screennail`), compare brightness, white balance and sharpness across cameras, warn before the scan continues.
10. **Live blur and overlap hints.** On-device feature matching between consecutive thumbnails (ORB via `opencv_dart`) gives real overlap percentages instead of heading guesses.
11. **Shutter skew measurement.** Point all cameras at the phone showing a millisecond clock, capture, read the clock in each image (OCR), store the per-camera offset with the project.
12. **GPMF extraction.** HERO cameras write their own IMU, GPS and exposure time into every file. Parse it on import and merge it with the phone log for exact per-frame timing.
13. **Labs firmware detection.** Detect Labs firmware over BLE (firmware string) and only offer the QR route when present; otherwise guide through the Protune menu.
14. **Battery and storage dashboard**: per-camera status is in Rig control (2 Nov); still open: warnings before a project starts with warnings before a project starts (lowest battery, least space, estimated shots left).
15. **Stable camera order.** Assign each camera a rig position once (front-left, top, ...). Use it in file names, in exports and in the COLMAP rig config.
16. **Export packages** for RealityCapture, Metashape, COLMAP (`rig_config.json` with fixed relative poses), Nerfstudio and Postshot, created from imported files plus sensor priors.
17. **Upload to the receiver while capturing** (when the phone has a second network), so nothing waits for the end.

### P2: makes it outstanding

18. **Lixel-style live coverage.** Model after XGRIDS Lixel's view: a live map of where the rig has been, coloured by how many cameras saw each area and from how many angles; areas seen from only one angle in amber; red where nothing was captured.
    - LiDAR iPhones: ARKit scene reconstruction mesh, each triangle coloured by viewing-angle count from the projected camera frustums (using the rig geometry).
    - Android with ARCore Depth: the same from depth images.
    - Other phones: VIO pose path from ARCore/ARKit instead of GPS (centimetres instead of metres) with frustum footprints on the ground plane.
    - Loop-closure hint when the path returns near its start; floor-level slices for multi-storey buildings.
19. **ARKit/ARCore pose recording** for every shot (6-DoF, timestamped), exported as initial poses. Cuts alignment time and fixes scale.
20. **Phone camera as an extra rig camera** (wide + ultra-wide), triggered with the GoPros.
21. **Generic Bluetooth drivers.** Insta360, DJI Osmo Action, Sony remote protocol, and a generic BLE shutter/trigger (HID). The coordinator already supports any `RigCamera`.
22. **Processing hand-off.** Optional job submission to a self-hosted reconstruction server (COLMAP + gsplat / Postshot CLI) with status and preview download.
23. **Field mode.** Large controls, haptic shot confirmation, audio cues per camera, screen-off capture, Apple Watch / Wear OS remote.
24. **Team mode.** Two phones on one rig (control + monitor), shared project via the receiver.
25. **More languages** once ARB files are in place (French, Spanish, Dutch are the next largest scanning markets in Europe).

## 3b. Toward the best scanning tool (review of 2 Nov)

Ordered by value for real scans. Effort: S (hours), M (days), L (weeks).

### Capture quality

| # | Idea | Why | Effort |
| --- | --- | --- | --- |
| C1 | **Pre-flight check** before *Start*: battery, card space ("enough for 38 min at 1 s"), heat, settings equal on all cameras, clocks synced, keep-awake on, GPS lock. One green/red list. | Most failed scans are a flat battery or a full card found out afterwards. | S |
| C2 | **Missed-shot watchdog for camera-timer mode**: poll the photo counter (status 38) every few seconds; alarm when a camera falls behind or stops. | Camera timers are fast but unconfirmed; this restores trust. | S |
| C3 | **Speed coach**: max walking speed from interval, lens FOV and subject distance (LiDAR/ARCore depth) for â‰¥70 % overlap; haptic warning when too fast. | Overlap is what makes or breaks reconstruction. | M |
| C4 | **Exposure match after the first shot**: fetch one screennail per camera, compare ISO/shutter/WB from EXIF and brightness; warn on mismatch. | Mismatched exposure is the second most common failure. | M |
| C5 | **Blur check** on screennails (Laplacian variance) with a "retake this position" hint. | Catches motion blur on site, not at the desk. | M |
| C6 | **Rig calibration**: ChArUco board captured by all cameras gives intrinsics and fixed relative poses, stored in the rig profile and exported as COLMAP `rig_config.json`. | Fixed-rig constraints make alignment faster and more robust. | L |
| C7 | **6-DoF phone poses** (ARCore/ARKit VIO, LiDAR depth on iPhone Pro) per shot, Lixel-style coverage mesh coloured by view count. | Real coverage instead of compass heading, metric scale for free. | L |
| C8 | **Scan templates**: object (turntable/orbits), room, faÃ§ade, corridor, pole/aerial; each sets interval, timing, lens, overlap target and guidance. | New users get good captures without knowing the theory. | S |
| C9 | **Video-for-splats pipeline**: on import, extract the sharpest frame per time window at a chosen fps. | Video capture is easier; splat tools want sharp stills. | M |
| C10 | **Phone camera as an extra rig camera** (wide + ultra-wide) triggered with the GoPros. | Free extra viewpoints. | M |

### Connectivity and transfer

| # | Idea | Why | Effort |
| --- | --- | --- | --- |
| T1 | **COHN**: all cameras on the phone hotspot or a router at once: parallel downloads, live previews from every camera, no Wi-Fi switching, no Android prompt per camera. | Biggest time saver for rigs; also fixes the per-camera join timeouts. | L |
| T2 | **Background service** for imports and uploads (Android foreground service, iOS background URLSession), progress notification, resumes after the app is closed. | A 50 GB import should not need the screen on. | M |
| T3 | **Byte-based progress with speed and time left** for imports (now counts files, so a 4 GB chapter looks frozen for minutes). | Users cancelled imports that were working. | S |
| T4 | **Multipart S3 upload** (parallel parts, >5 GB files, resume per part) and **upload while capturing** when a second network is available. | Videos above 5 GB cannot be uploaded today. | M |
| T5 | **Verified clean-up**: after an import (and optionally the server upload) is verified by checksum, offer *Erase cameras* and *Free phone storage* in one step. | Closes the loop: shoot â†’ import â†’ upload â†’ erase. | S |
| T6 | **5 GHz camera Wi-Fi** (setting 178) when the phone supports it. | Roughly double transfer speed. | S |
| T7 | **USB-C import** (MTP over OTG) as the fallback for huge videos. | Fastest path when Wi-Fi is the bottleneck. | M |
| T8 | **Auto-reconnect during capture** with pause/resume of the interval. | One dropped camera currently ends the run. | M |

### Data and processing

| # | Idea | Why | Effort |
| --- | --- | --- | --- |
| D1 | **Export packages**: COLMAP (with rig sets and priors), Nerfstudio `transforms.json`, Metashape XML, RealityScan, Postshot. | Hand-off without manual sorting. | M |
| D2 | **Processing hand-off**: send a project to a self-hosted COLMAP/GLOMAP + gsplat or Postshot server, show status, download the splat and preview it in the app. | From capture to result in one tool. | L |
| D3 | **GPMF extraction**: camera IMU, GPS and exact exposure time per frame merged with the phone log. | Exact timing replaces estimated camera-timer events. | M |
| D4 | **Project notes and site photos**, tags, map of all projects, search. | Real projects need context. | S |
| D5 | **Per-project storage budget** and a warning when the phone runs low. | Imports fail late when the phone is full. | S |

### App quality

| # | Idea | Why | Effort |
| --- | --- | --- | --- |
| Q1 | **Onboarding**: permissions wizard and a first-scan tutorial. | Permission pop-ups mid-task confuse users. | S |
| Q2 | **Field mode**: large controls, volume-button shutter, screen-off capture, watch remote. | Gloves, sun, one free hand. | M |
| Q3 | **Rig designer**: name and place each camera (front, left, up), colour per camera everywhere. | Files and sets become understandable. | S |
| Q4 | **One upload settings page** (storage server and receiver merged, single auto-upload). | Two sections with two switches confuse. | S |
| Q5 | **ARB translations** instead of three dictionary mechanisms; more languages. | Maintainability. | M |
| Q6 | **Dark-only screens** (capture, coverage viewer, live monitor) follow the theme or stay dark on purpose with matching dialogs. | Consistency. | S |
| Q7 | **Large-font and tablet layouts** (buttons that wrap, two-pane on tablets) instead of the portrait lock. | Accessibility. | M |
| Q8 | **Crash and log export** (opt-in), one-tap "send diagnostics". | Field bugs are otherwise invisible. | S |
| Q9 | **GoPro simulator** (fake BLE + HTTP) for integration tests in CI. | Most bugs found today only showed on hardware. | M |
| Q10 | **More cameras**: Insta360 X4/X5, DJI Osmo Action, generic BLE shutter. | The coordinator already supports any `RigCamera`. | L |
| Q11 | **iPhone test pass** incl. LiDAR, background and Wi-Fi join. | Untested platform. | M |
| Q12 | **Store release**: signing, privacy manifest, bundle ID, screenshots. | Distribution. | M |

### Known imperfections still open (found 2 Nov)

- First camera Wi-Fi join can time out without Android's prompt (one automatic retry added; COHN removes the problem).
- HERO13 sometimes drops the HTTP connection in the middle of a 4 GB chapter and stops answering Bluetooth for a minute; downloads now resume up to four times, and a silent camera is marked disconnected after 15 s.
- Import progress is per file, not per byte (T3).
- Old projects without `run_started_utc` split runs by a 10 s gap.
- `isRecording` is refreshed only every 30 s outside Rig control.

## 4. Defaults review

| Setting | Before | Now | Reason |
| --- | --- | --- | --- |
| Language | English | English | as requested |
| Preset | Outdoor Scan | Outdoor Scan | Photo, Standard (no SuperPhoto/HDR processing), Linear, portrait, target ISO 100 |
| Interval | 1 s | 1 s | measured after the slowest camera finishes, never queues |
| Coverage viewer | on, hidden on non-LiDAR phones | on, interactive everywhere | |
| GPS log rate | 2 s | 1 s | phones deliver ~1 Hz fixes; 2 s dropped half |
| IMU rate | 20 Hz | 20 Hz | enough for per-shot attitude; raise to 100 Hz only for video |
| Camera clock | untouched | set to phone time on connect | aligned file timestamps across the rig |
| Control mode | untouched | shown as "Cameras differ" | Pro mode is required for the full settings list; one of the test cameras was in Easy mode |

## 5. License

Decided 30 Oct 2026: **Apache-2.0** (was MIT). Permissive and store-compatible, with an explicit patent grant and a requirement to mark changes. The license does not cover the name or logo; [NOTICE](../NOTICE) states that "KOSMOS 3D" and its logos stay with Kreativ Institut OWL, so forks must rebrand. GPL/AGPL were ruled out because they conflict with App Store terms.

Still to do for store release: register the word mark "KOSMOS 3D" (DPMA or EUIPO) if you want legal protection beyond the notice.
