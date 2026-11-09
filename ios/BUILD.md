# iOS build and hardware acceptance

This checkout needs macOS and Xcode to compile the native Swift code. Windows
Flutter analysis and Android builds cannot validate Swift or produce an IPA.

Quick install on a connected iPhone: `bash ios/run-on-iphone.sh` (free Apple ID)
or `bash ios/run-on-iphone.sh --paid`. The manual steps are below.

1. Install the Flutter version declared by `.metadata`/the project toolchain and
   Xcode with its iOS SDK. Run `flutter doctor -v` and resolve iOS requirements.
2. Run `flutter pub get`, then `flutter build ios --debug --no-codesign` on the Mac.
3. Open `ios/Runner.xcworkspace`, select your Apple signing team and a unique
   bundle identifier. Enable Hotspot Configuration to match Runner.entitlements.
4. Select the iPhone and run. Allow Bluetooth, local network, motion, camera and
   location as needed. Photos permission is requested only when exporting.
5. For distribution, configure signing and run `flutter build ipa --release`.

## Without a Mac (Windows)

The GitHub Actions workflow `.github/workflows/build.yml` builds an unsigned
`kosmos3d-unsigned.ipa` on a macOS runner for every push. Download the
`kosmos3d-ios-unsigned-ipa` artifact and install it with Sideloadly or AltStore,
signed with your Apple ID:

- Free Apple ID: the app runs for 7 days, then re-sign. The Hotspot
  Configuration capability is unavailable, so one-tap camera Wi-Fi join falls
  back to joining in iOS Settings (the app shows SSID, password and a Wi-Fi QR).
- Paid developer account (99 USD/year): one-year profiles, Hotspot
  Configuration works, and TestFlight distribution becomes possible.

Native additions: direct GoPro Wi-Fi joining through NEHotspotConfiguration;
Photos export; Files-visible exports; ARKit sceneDepth sampling with confidence
filtering, camera transform, intrinsics and monotonic timestamps; bounded preview
and PLY export. Depth requires a runtime capability check and iOS 14+.

Acceptance on iPhone 12 Pro + HERO13 Black: first pairing, denied permissions,
Wi-Fi join refusal, sequential multi-camera imports, repeated import, Files and
Photos verification, LAN server uploads, depth permission/limited tracking,
app backgrounding, thermal limits, interruption and a second capture session.
GoPro live video decoding remains Android-only; iOS must show its fallback label.
The measured cloud is a phone-depth preview, not registered GoPro coverage.

Before App Store submission: replace development identifiers, review privacy
manifests and data collection declarations, eliminate broad HTTP ATS exceptions
where possible, implement durable background transfers, test VoiceOver and large
text, and finish localization. No signed distribution artifact is supplied here.
