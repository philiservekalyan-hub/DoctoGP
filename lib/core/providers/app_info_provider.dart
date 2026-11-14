// lib/core/providers/app_info_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads versionName + buildNumber from the platform's build metadata,
/// which originates from `version:` in pubspec.yaml.
final appInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

/// Convenience: "v1.0.0 (build 1)" or "v1.0.0" if buildNumber is empty.
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  final info = await ref.watch(appInfoProvider.future);
  final build = info.buildNumber.trim();
  return build.isEmpty
      ? 'v${info.version}'
      : 'v${info.version} (build $build)';
});