import Flutter
import UIKit
import NetworkExtension
import Photos
import ARKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var native: KosmosNative?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KosmosNative") {
      native = KosmosNative(messenger: registrar.messenger())
    }
  }
}

/// Foreground camera import, Photos export, and measured ARKit scene-depth capture.
final class KosmosNative: NSObject, ARSessionDelegate {
  private let session = ARSession()
  private var output: URL?
  private var points: [String: SIMD3<Float>] = [:]
  private var joinedSSID: String?
  private var active = false
  private var tracking = "Not started"
  private var lastFrameTimestamp: TimeInterval = -1

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    session.delegate = self
    session.delegateQueue = .main
    FlutterMethodChannel(name: "com.kosmos3d.kosmos3d/system_settings", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.system(call, result) }
    FlutterMethodChannel(name: "com.kosmos3d/lidar", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in self?.depth(call, result) }
  }

  private func fail(_ result: FlutterResult, _ message: String) {
    result(FlutterError(code: "KOSMOS_NATIVE", message: message, details: nil))
  }

  private func system(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "joinCameraWifi":
      guard let ssid = args["ssid"] as? String, let password = args["password"] as? String else {
        fail(result, "Missing Wi-Fi credentials"); return
      }
      let config = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
      config.joinOnce = true
      NEHotspotConfigurationManager.shared.apply(config) { error in
        DispatchQueue.main.async {
          if let error = error as NSError?,
             !(error.domain == NEHotspotConfigurationErrorDomain && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue) {
            self.fail(result, error.localizedDescription)
          } else { self.joinedSSID = ssid; result(true) }
        }
      }
    case "keepScreenOn":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      UIApplication.shared.isIdleTimerDisabled = on
      result(true)
    case "startCaptureService", "stopCaptureService":
      // iOS keeps Bluetooth running in the background (bluetooth-central mode).
      result(true)
    case "releaseCameraWifi":
      if let ssid = joinedSSID { NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid) }
      joinedSSID = nil; result(true)
    case "openWifiSettings", "openTetheringSettings":
      // iOS does not provide a public deep link to the Wi-Fi pane.
      fail(result, "Open iOS Settings > Wi-Fi manually, or use Import all to join in the app.")
    case "saveToDownloads":
      guard let source = args["sourcePath"] as? String, let relative = args["relativePath"] as? String else {
        fail(result, "Missing export path"); return
      }
      let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
      guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." && !$0.contains("\\") && !$0.contains(":") }) else {
        fail(result, "Invalid export path"); return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          let target = documents.appendingPathComponent("Exports/\(relative)")
          try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
          // Unique exports preserve earlier user copies.
          let final = FileManager.default.fileExists(atPath: target.path)
            ? target.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString)-\(target.lastPathComponent)") : target
          try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: final)
          DispatchQueue.main.async { result(final.path) }
        } catch { DispatchQueue.main.async { self.fail(result, error.localizedDescription) } }
      }
    case "saveToDeviceGallery":
      guard let source = args["sourcePath"] as? String else { fail(result, "Missing media"); return }
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          DispatchQueue.main.async { self.fail(result, "Photos permission denied; original remains in the app") }; return
        }
        let url = URL(fileURLWithPath: source)
        let isVideo = url.pathExtension.lowercased() == "mp4"
        guard isVideo || ["jpg", "jpeg", "png", "heic"].contains(url.pathExtension.lowercased()) else {
          DispatchQueue.main.async { self.fail(result, "Use Files export for this media type") }; return
        }
        var identifier: String?
        PHPhotoLibrary.shared().performChanges({
          let request = isVideo ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
          identifier = request?.placeholderForCreatedAsset?.localIdentifier
        }) { success, error in
          DispatchQueue.main.async {
            if success, let identifier = identifier { result(identifier) }
            else { self.fail(result, error?.localizedDescription ?? "Photos export failed") }
          }
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func depth(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "checkLidarAvailable": result(ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth))
    case "startDepthCapture":
      guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            let path = args["outputDir"] as? String else { fail(result, "LiDAR or output directory unavailable"); return }
      AVCaptureDevice.requestAccess(for: .video) { allowed in
        DispatchQueue.main.async {
          guard allowed else { self.fail(result, "Camera permission is required for depth tracking"); return }
          do {
            self.output = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: self.output!, withIntermediateDirectories: true)
            self.points.removeAll()
            self.lastFrameTimestamp = -1
            let config = ARWorldTrackingConfiguration()
            config.frameSemantics = .sceneDepth
            self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.active = true; self.tracking = "Initializing"; result(true)
          } catch { self.fail(result, error.localizedDescription) }
        }
      }
    case "captureDepthFrame":
      guard active, let frame = session.currentFrame, let depth = frame.sceneDepth, let output = output else {
        fail(result, "No depth frame yet"); return
      }
      guard case .normal = frame.camera.trackingState else { fail(result, "Tracking limited; move slowly toward textured surfaces"); return }
      guard frame.timestamp > lastFrameTimestamp, depth.confidenceMap != nil else { fail(result, "Waiting for a new confident depth frame"); return }
      lastFrameTimestamp = frame.timestamp
      let map = depth.depthMap
      let confidence = depth.confidenceMap
      CVPixelBufferLockBaseAddress(map, .readOnly)
      if let confidence = confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
      defer {
        CVPixelBufferUnlockBaseAddress(map, .readOnly)
        if let confidence = confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
      }
      let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
      guard let base = CVPixelBufferGetBaseAddress(map) else { fail(result, "Empty depth map"); return }
      let row = CVPixelBufferGetBytesPerRow(map)
      let intrinsic = frame.camera.intrinsics
      let sx = Float(width) / Float(frame.camera.imageResolution.width)
      let sy = Float(height) / Float(frame.camera.imageResolution.height)
      let fx = intrinsic[0][0] * sx, fy = intrinsic[1][1] * sy
      let cx = intrinsic[2][0] * sx, cy = intrinsic[2][1] * sy
      var samples: [[Float]] = []
      for y in stride(from: 0, to: height, by: 4) {
        let depths = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self)
        for x in stride(from: 0, to: width, by: 4) {
          if let c = confidence, let cb = CVPixelBufferGetBaseAddress(c) {
            let level = cb.advanced(by: y * CVPixelBufferGetBytesPerRow(c)).assumingMemoryBound(to: UInt8.self)[x]
            if level < 2 { continue }
          }
          let z = depths[x]
          guard z.isFinite && z > 0.2 && z < 6 else { continue }
          // ARKit camera looks along -Z; image Y points down.
          let local = SIMD4<Float>((Float(x) - cx) * z / fx, -(Float(y) - cy) * z / fy, -z, 1)
          let world = frame.camera.transform * local
          let p = SIMD3<Float>(world.x, world.y, world.z)
          samples.append([p.x, p.y, p.z])
          let key = "\(Int(floor(p.x / 0.04))),\(Int(floor(p.y / 0.04))),\(Int(floor(p.z / 0.04)))"
          if points.count < 60000 || points[key] != nil { points[key] = p }
        }
      }
      let index = args["index"] as? Int ?? 0
      let path = output.appendingPathComponent(String(format: "depth_%06d.json", index))
      let matrix = (0..<4).flatMap { column in (0..<4).map { row in frame.camera.transform[column][row] } }
      let data: [String: Any] = ["timestampMonotonicSeconds": frame.timestamp,
        "savedAtUTC": ISO8601DateFormatter().string(from: Date()), "coordinateSystem": "ARKit world, metres, Y up",
        "cameraToWorldColumnMajor": matrix, "depthIntrinsics": [fx, fy, cx, cy],
        "depthSize": [width, height], "sampleStride": 4, "confidenceMinimum": 2, "points": samples]
      do { try JSONSerialization.data(withJSONObject: data).write(to: path, options: .atomic); result(path.path) }
      catch { fail(result, error.localizedDescription) }
    case "getPreviewPoints":
      let values = Array(points.values)
      let step = max(1, values.count / 12000)
      let sampled = stride(from: 0, to: values.count, by: step).map { i in [values[i].x, values[i].y, values[i].z] }
      result(["points": sampled, "tracking": tracking, "voxelCount": points.count])
    case "stopDepthCapture": session.pause(); active = false; tracking = "Stopped"; result(true)
    case "exportPointCloud":
      guard let output = output else { fail(result, "No depth capture"); return }
      let snapshot = Array(points.values)
      DispatchQueue.global(qos: .utility).async {
        let header = "ply\nformat ascii 1.0\ncomment ARKit measured depth; metres; Y up\nelement vertex \(snapshot.count)\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
        let text = header + snapshot.map { "\($0.x) \($0.y) \($0.z)" }.joined(separator: "\n")
        let path = output.appendingPathComponent("measured-cloud.ply")
        do { try text.write(to: path, atomically: true, encoding: .utf8); DispatchQueue.main.async { result(path.path) } }
        catch { DispatchQueue.main.async { self.fail(result, error.localizedDescription) } }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    switch camera.trackingState {
    case .normal: tracking = "Tracking"
    case .limited: tracking = "Limited tracking"
    case .notAvailable: tracking = "Tracking unavailable"
    }
  }
  func session(_ session: ARSession, didFailWithError error: Error) { tracking = error.localizedDescription; active = false }
  func sessionWasInterrupted(_ session: ARSession) { tracking = "Interrupted" }
  func sessionInterruptionEnded(_ session: ARSession) {
    // Do not merge a potentially reset coordinate origin into the previous cloud.
    session.pause(); active = false; tracking = "Start a new session after interruption"
  }
}
