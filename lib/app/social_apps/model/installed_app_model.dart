class InstalledApp {
  final String packageName;
  final String appName;
  final String? iconPath;
  final bool isSystemApp;
  final String? versionName;
  final int? versionCode;

  InstalledApp({
    required this.packageName,
    required this.appName,
    this.iconPath,
    required this.isSystemApp,
    this.versionName,
    this.versionCode,
  });

  factory InstalledApp.fromJson(Map<String, dynamic> json) {
    return InstalledApp(
      packageName: json['packageName'] ?? '',
      appName: json['appName'] ?? '',
      iconPath: json['iconPath'],
      isSystemApp: json['isSystemApp'] ?? false,
      versionName: json['versionName'],
      versionCode: json['versionCode'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'appName': appName,
      'iconPath': iconPath,
      'isSystemApp': isSystemApp,
      'versionName': versionName,
      'versionCode': versionCode,
    };
  }
}
