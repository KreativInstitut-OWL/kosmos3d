class CameraDevice {
  final String id;
  final String name;
  final String? customName;
  bool isConnected;
  int batteryLevel; // 0 to 100
  String storageRemaining; // e.g., "1h 45m" or "32GB"
  bool isRecording;
  bool isWifiConnected;
  String? wifiIpAddress;
  Map<String, String> currentSettings;

  String get displayName =>
      customName != null && customName!.isNotEmpty ? customName! : name;

  CameraDevice({
    required this.id,
    required this.name,
    this.customName,
    this.isConnected = false,
    this.batteryLevel = 100,
    this.storageRemaining = "Unknown",
    this.isRecording = false,
    this.isWifiConnected = false,
    this.wifiIpAddress,
    Map<String, String>? currentSettings,
  }) : currentSettings = currentSettings ?? {};

  // Helper method to simulate a copy with changed state
  CameraDevice copyWith({
    String? id,
    String? name,
    String? customName,
    bool? isConnected,
    int? batteryLevel,
    String? storageRemaining,
    bool? isRecording,
    bool? isWifiConnected,
    String? wifiIpAddress,
    Map<String, String>? currentSettings,
  }) {
    return CameraDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      customName: customName ?? this.customName,
      isConnected: isConnected ?? this.isConnected,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      storageRemaining: storageRemaining ?? this.storageRemaining,
      isRecording: isRecording ?? this.isRecording,
      isWifiConnected: isWifiConnected ?? this.isWifiConnected,
      wifiIpAddress: wifiIpAddress ?? this.wifiIpAddress,
      currentSettings: currentSettings ?? Map.from(this.currentSettings),
    );
  }
}
