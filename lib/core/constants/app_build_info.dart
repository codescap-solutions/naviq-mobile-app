/// App version reported on location posts (diagnostics only — lets the backend
/// tell which build produced a fix). Must match `version:` in pubspec.yaml;
/// test/core/constants/app_build_info_test.dart fails if they drift apart.
class AppBuildInfo {
  const AppBuildInfo._();

  static const String version = '1.0.10';
  static const String build = '31';
}
