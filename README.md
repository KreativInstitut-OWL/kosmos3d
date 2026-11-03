<p align="center">
  <img src="assets/icon/app_icon.png" width="104" alt="KOSMOS 3D" />
</p>

<h1 align="center">KOSMOS 3D</h1>

<p align="center">
  <strong>Run a whole camera rig from one phone.</strong><br />
  Connect every camera, give them identical settings, trigger them together,<br />
  and bring every original home with its sensor data.
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-2.1-55FC27?style=flat-square&labelColor=0A0C0B" />
  <img alt="Android and iOS" src="https://img.shields.io/badge/Android%20%C2%B7%20iOS-55FC27?style=flat-square&labelColor=0A0C0B" />
  <img alt="Local first" src="https://img.shields.io/badge/data-stays%20on%20your%20phone-55FC27?style=flat-square&labelColor=0A0C0B" />
  <img alt="Languages" src="https://img.shields.io/badge/English%20%C2%B7%20Deutsch-55FC27?style=flat-square&labelColor=0A0C0B" />
  <img alt="License" src="https://img.shields.io/badge/license-Apache%202.0-55FC27?style=flat-square&labelColor=0A0C0B" />
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#your-first-scan">First scan</a> ·
  <a href="#getting-the-files-off-the-cameras">Files</a> ·
  <a href="#storage-server">Storage server</a> ·
  <a href="#build-it-yourself">Build</a> ·
  <a href="#releases">Releases</a> ·
  <a href="#contributing-and-support">Contribute</a> ·
  <a href="#license-and-imprint">License</a>
</p>

<p align="center">
  <img src="docs/screenshots/home.png" width="200" alt="Home screen" />
  <img src="docs/screenshots/camera-networks.png" width="200" alt="Camera networks" />
  <img src="docs/screenshots/all-settings.png" width="200" alt="All camera settings" />
</p>

---

## What it is

KOSMOS 3D is a field tool for capturing real places with several cameras at once, for photogrammetry and Gaussian splatting. Mount the cameras and your phone on a rig, and the phone becomes the control desk:

- **Connect** every camera over Bluetooth. No pairing in the phone's system settings.
- **Match** settings across the rig. The app asks each camera what it supports, shows only values that every camera shares, writes them, and reads them back.
- **Capture** on all cameras at the same moment, photo by photo on an interval or as continuous video.
- **Record** the phone's GPS, compass, gyroscope, accelerometer and barometer with every shot. On iPhones with LiDAR it also records measured depth.
- **Collect** the originals from every camera over Wi-Fi, with a checksum for each file.
- **Upload** whole projects to your own storage: any S3-compatible bucket, or the small receiver that runs on your computer.

Today the camera driver speaks [Open GoPro](https://gopro.github.io/OpenGoPro/) (HERO9 and newer, tested with HERO13 Black). Everything above the driver (projects, sync, transfers, sensors, uploads) talks to a generic camera interface, so other Bluetooth cameras and triggers can be added as drivers.

> Not affiliated with GoPro. GoPro, HERO and their logos are trademarks of GoPro, Inc.

## What you need

| | |
| --- | --- |
| Phone | Android 7+ with Bluetooth LE, or iPhone with iOS 14+. A LiDAR iPhone (12 Pro and newer Pro models) adds measured depth. |
| Cameras | GoPro HERO9 Black or newer. Mixed models work; the app limits settings to what all of them share. |
| Optional | GoPro Labs firmware, to set ISO and white balance on every camera with one QR code. A computer for the receiver, or an S3 bucket. |

## Install

### Android

1. On your phone, open **[the latest release](../../releases/latest)** and tap `kosmos3d.apk`. Direct link: [`releases/latest/download/kosmos3d.apk`](../../releases/latest/download/kosmos3d.apk).
2. Allow installing from your browser when Android asks, then open the APK.
3. On first launch, allow **Nearby devices** and **Location**. Android needs both to find Bluetooth cameras.

Updates install over the old version and keep your projects. Every change on `main` publishes a new release automatically.

### iPhone

App Store and TestFlight builds are planned. Until then you have two routes:

- **With a Mac:** open `ios/Runner.xcworkspace` in Xcode, choose your team under *Signing & Capabilities*, connect the iPhone and press Run. Details in [ios/BUILD.md](ios/BUILD.md).
- **Without a Mac:** every build produces `kosmos3d-ios-unsigned-ipa` in [Actions](../../actions/workflows/build.yml). Install it with [Sideloadly](https://sideloadly.io/) or AltStore using your Apple ID. See [ios/BUILD.md](ios/BUILD.md).

Allow **Bluetooth**, **Local Network** and **Location** when asked.

## Your first scan

1. **Prepare the cameras.** Switch them on and enable *Wireless Connections* in each camera's menu. Mount them in portrait.
2. **Connect.** Open **Cameras** and tap *Connect all*. The app scans first and connects every camera it finds. A camera that is off is reported as *not found* and leaves the others alone. Known cameras keep their place in the list.
3. **Match the rig.** Tap the sliders icon for **All camera settings**. Anything marked *Cameras differ* is worth fixing now. Switch *Control mode* to **Pro** on all cameras to unlock the full list.
4. **Set exposure.** Show every camera the *ISO / white balance* QR from **All camera settings** (needs GoPro Labs firmware; ISO 100 and 5500 K by default), or set them once in each camera's Protune menu.
5. **New project.** Name it and keep **Outdoor Scan** (photo, Linear lens, 1 s interval, target ISO 100) or pick another preset. *Start* checks every camera before the first shot. If one disagrees, you are told which camera and which setting.
6. **Capture.** Walk slowly. The coverage view shows where you have been and which directions are still empty. Tap *Stop* when you are done.

**Interval timing** decides who keeps the beat:

- **Camera timer** (default): every camera runs its own photo timer, started by one command to all of them. The interval is exact (measured 1.001 s on HERO13) and the cameras start within about 0.1 s of each other. At *Stop* the app counts the photos on each card, so a last shot taken while Stop was on its way still gets its set.
- **App (confirmed)**: the app fires each shot and waits until every camera has saved it. Every shot is confirmed, but a HERO13 needs about 3 s per round.

**Rig control** (the remote icon in **Cameras**) works on all selected cameras at once: modes, shutter, clocks, Wi-Fi, GPS, keep-awake, sleep and power, and erasing the cards.

## Getting the files off the cameras

Bluetooth is too slow for photos, so the originals come over each camera's own Wi-Fi.

**Cameras → Camera networks** reads every camera's Wi-Fi name and password over Bluetooth. Nothing to type. From there:

- **Import all files** joins each camera in turn, copies every original into the project, verifies it with SHA-256, and moves on. Android asks once per camera, iPhone shows a *Join network* prompt.
- **Import this project's files** takes only what was shot during this project's runs.
- **Join** connects to one camera, for browsing or picking single files. The phone sees one camera's Wi-Fi at a time, so *Browse* lists the camera you joined.
- **Show password / QR** lets a laptop or a second phone join a camera directly.

Where files go:

- Originals are stored **in the app**, per project: `kosmos3d_projects/<project>/captures/<serial>_<folder>_<file>`. Next to each file is a `.receipt.json` with its source path, size and checksum.
- After an import, `rig_sets.json` groups the photos into sets, one per shutter event, by the time each camera took them. Each camera is lined up by its first photo of the run, so a camera that missed a shot leaves a gap in that set instead of shifting all later ones. Extra photos are listed as unmatched.
- With *Also copy to Photos / Gallery* on, a copy goes to `DCIM/KOSMOS3D` on Android or the Photos app on iPhone.
- **Transfers → Save to phone** copies a project to `Downloads/KOSMOS3D` (Android) or *Files → KOSMOS 3D* (iPhone).

Large videos survive dropped connections: an interrupted download continues where it stopped. **Transfers → View files** shows everything you imported.

**Erasing cards.** *Rig control → Erase all files* empties the selected cards and checks they read zero files afterwards. A card holding files that are in no project is skipped, and you have to confirm a second time to erase it anyway.

## Storage server

**Settings → Storage server** uploads whole projects to a bucket you own. It works with every S3-compatible service: AWS S3, Wasabi, Cloudflare R2, MinIO, Backblaze B2, or a NAS that speaks S3.

| Field | Example |
| --- | --- |
| Endpoint URL | `https://s3.eu-central-003.backblazeb2.com` |
| Region | `eu-central-003` (left empty, it is read from the endpoint where possible) |
| Bucket | `my-scans` |
| Access key ID / Secret key | from your provider, limited to this one bucket |
| Folder in bucket | `kosmos3d` |

Projects land in `bucket/folder/<project>_<id>/` with the same layout as on the phone: originals, receipts, sensor logs, LiDAR. A file already on the server with the same size is skipped, so an interrupted upload can simply be started again. *Test* tells you exactly what's wrong: unknown key, wrong secret or region, missing bucket, no permission.

Keys are entered on each phone and kept in its secure storage (Keychain / Android Keystore). They are never built into the app or written to project files. Give every person or team a key that can only reach their own bucket.

## Windows receiver

If you would rather keep everything on your own computer, run the receiver from this repository:

```powershell
cd server
.\start_receiver.ps1 -Storage D:\KOSMOS3D_UPLOADS -Port 8787
```

The first start creates a private token in `%LOCALAPPDATA%\KOSMOS3D\receiver-token.txt`. In the app, open **Settings → KOSMOS receiver**, enter `http://<your-computer-ip>:8787` and the token. Phone and computer must be on the same network. Every file is checked with SHA-256 before it is stored, ready for your reconstruction software on the same machine. More in [server/README.md](server/README.md).

## Sensors and coverage

Every shot writes one line to the project's sensor log: time, GPS position and accuracy, compass heading, phone attitude as a quaternion, barometric pressure, and which cameras fired. Use it to speed up alignment in COLMAP, RealityCapture, Metashape or Nerfstudio.

- **LiDAR iPhones** record measured depth frames and show the point cloud live while you scan.
- **Other phones** show the poses in an orbit view (drag to rotate, pinch to zoom, top and front views) coloured by density or height, plus a walking-speed warning.

*Capture guidance* in the project settings tells you during capture where a direction is missing, when you walk too fast, and when two shots are too similar.

Planned features are tracked in [docs/ROADMAP.md](docs/ROADMAP.md).

## Build it yourself

You need [Flutter](https://flutter.dev/) (stable channel) and, for iOS, a Mac with Xcode.

```bash
git clone https://github.com/KreativInstitut-OWL/kosmos3d.git
cd kosmos3d
flutter pub get
flutter test
flutter run
```

Before opening a pull request, run all checks:

```bash
flutter analyze
flutter test
python -m unittest discover -s server -p "test_*.py"
```

Project layout:

| Path | What lives there |
| --- | --- |
| `lib/services/gopro_service.dart` | Camera driver: Bluetooth control, settings, Wi-Fi import, erase |
| `lib/services/gopro_protocol.dart` | Open GoPro packet framing and response matching |
| `lib/services/gopro_setting_catalog.dart` | Every Open GoPro setting and value, generated from the official spec |
| `lib/services/capture_coordinator.dart` | Rig state machine: synchronise, start, interval, stop, recover |
| `lib/services/rig_sets.dart` | Groups imported photos into rig sets by capture time |
| `lib/services/cloud_storage_service.dart` | S3-compatible uploads (SigV4) |
| `lib/l10n/` | English and German text |
| `server/` | Windows / Python receiver |
| `.github/workflows/build.yml` | Tests, signed Android release, unsigned iOS build |

### Adding another camera or Bluetooth device

Implement `CameraServiceInterface` (connect, trigger, stop, apply settings) for the device, plus the `RigCamera` contract used by the capture coordinator (`configure`, `verifyReady`, `start`, `stop`, `photoCount`). The coordinator does not know about GoPro. Any device that can confirm "ready" and "started" fits the same synchronised capture flow.

## Releases

Every push to `main` runs the [Build workflow](../../actions/workflows/build.yml): analyze, tests, a signed APK published as a GitHub release, and an unsigned iOS build. Pull requests run the same checks without publishing.

Android only installs an update if it is signed with the same key as the version on the phone. The workflow reads that key from four repository secrets (*Settings → Secrets and variables → Actions*):

| Secret | Value |
| --- | --- |
| `KOSMOS_KEYSTORE_BASE64` | the release keystore, base64-encoded |
| `KOSMOS_KEYSTORE_PASSWORD` | keystore password |
| `KOSMOS_KEY_ALIAS` | key alias |
| `KOSMOS_KEY_PASSWORD` | key password |

For a signed local build, put the same values in `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; ignored by Git). Without it, local builds use the debug key. Keep a backup of the keystore: if it is lost, every user has to uninstall before the next update.

## Contributing and support

Bug reports and ideas: [open an issue](../../issues). Please include phone model, camera models and firmware, and what you expected.

Pull requests are welcome. Run the checks above, keep changes focused, and add English and German text for anything users see.

## Privacy

KOSMOS has no account, no analytics and no server of its own. Projects stay on your phone until you export or upload them to a destination you configured. Location is used only to tag your captures.

## License and imprint

KOSMOS 3D is open source under the [Apache License 2.0](LICENSE). You may use, change and redistribute the code, also commercially, as long as you keep the license and [NOTICE](NOTICE) and mark your changes.

The name **KOSMOS 3D** and its logos are not covered by the license. If you publish your own build or fork, give it a different name and icon.

**KOSMOS 3D** is developed by **Sam Wiemann** for the **Kreativ Institut OWL**.
Imprint and contact: [kreativ.institute](https://kreativ.institute/de)
