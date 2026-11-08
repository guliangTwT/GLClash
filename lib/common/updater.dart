import 'dart:convert' show LineSplitter;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' show sha256;
import 'package:gl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:path/path.dart' show basename, dirname;

import 'constant.dart';

/// The prefix each mirror channel prepends to a GitHub URL. The two proxies
/// serve the same files on different edges; measured throughput decides which
/// one a slow network wants, not geography alone.
const updateMirrorPrefixes = {
  UpdateChannel.mirror: 'https://gh-proxy.com/',
  UpdateChannel.mirrorOrg: 'https://gh-proxy.org/',
};

String updateApiUrl(UpdateChannel channel) {
  return rewriteUpdateUrl(
    'https://api.github.com/repos/$repository/releases/latest',
    channel,
  );
}

String updateLatestPageUrl(UpdateChannel channel) {
  return rewriteUpdateUrl(
    'https://github.com/$repository/releases/latest',
    channel,
  );
}

/// Codeberg answers only after GitHub, and is never proxied: the mirrors
/// forward GitHub alone.
String codebergApiUrl() =>
    'https://codeberg.org/api/v1/repos/$codebergRepository/releases/latest';

String codebergLatestPageUrl() =>
    'https://codeberg.org/$codebergRepository/releases/latest';

/// The same release file on Codeberg, where every release is published under
/// the same tag and asset name.
String codebergAssetUrl(String tag, String name) =>
    'https://codeberg.org/$codebergRepository/releases/download/$tag/$name';

/// The GitHub download URL for [name] under [tag], which is where a release
/// checked on Codeberg still points second.
String githubAssetUrl(String tag, String name) =>
    'https://github.com/$repository/releases/download/$tag/$name';

/// Points a GitHub URL at the chosen source. Only GitHub's own hosts are
/// rewritten, so a profile, icon-set or Codeberg URL never leaves through a
/// proxy just because the update channel is set to a mirror.
String rewriteUpdateUrl(String url, UpdateChannel channel) {
  final prefix = updateMirrorPrefixes[channel];
  if (prefix == null || !url.isGitHubUrl) {
    return url;
  }
  return '$prefix$url';
}

extension on String {
  bool get isGitHubUrl {
    final uri = Uri.tryParse(this);
    return uri != null &&
        (uri.host == 'github.com' || uri.host == 'api.github.com');
  }
}

/// The release asset this build replaces itself with.
///
/// [urls] lists the same file on every host that serves it; the download walks
/// them in order. [sha256] is absent on a payload that carries no checksum, and
/// the download then falls back to the size check alone.
typedef UpdateAsset = ({
  String name,
  List<String> urls,
  int size,
  String? sha256,
});

/// The checksum file every release publishes beside its binaries. GitHub
/// describes each asset's digest itself; Codeberg does not, so the standby host
/// reaches for this instead.
const sha256SumsAssetName = 'SHA256SUMS';

/// Reads `SHA256SUMS` into asset name → digest.
///
/// Accepts what `sha256sum` writes (`<64 hex>  <name>`, and the `<hash> *<name>`
/// binary form) plus the BSD checkfile form where the name comes first.
Map<String, String> parseSha256Sums(String text) {
  final sums = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final gnu = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(trimmed);
    if (gnu != null) {
      sums[gnu.group(2)!.trim()] = gnu.group(1)!.toLowerCase();
      continue;
    }
    // `SHA256 (name) = <hex>` — BSD/macOS `shasum -a 256 -c` output.
    final bsd = RegExp(
      r'^SHA256\s*\((.+)\)\s*=\s*([0-9a-fA-F]{64})$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (bsd != null) {
      sums[bsd.group(1)!.trim()] = bsd.group(2)!.toLowerCase();
    }
  }
  return sums;
}

/// Turns a Codeberg release into the release payload the rest of the updater
/// reads, so asset picking and version comparison stay in one place.
///
/// Null when the payload is not a usable release: without a tag or without a
/// single downloadable asset it counts as absent.
Map<String, dynamic>? releaseFromCodeberg(Object? data) {
  if (data is! Map) {
    return null;
  }
  final tag = data['tag_name'];
  if (tag is! String || tag.isEmpty) {
    return null;
  }
  final rawAssets = data['assets'];
  if (rawAssets is! List) {
    return null;
  }
  final assets = <Map<String, dynamic>>[];
  for (final raw in rawAssets) {
    if (raw is! Map) {
      continue;
    }
    final name = raw['name'];
    final url = raw['browser_download_url'];
    if (name is! String || name.isEmpty || url is! String || url.isEmpty) {
      continue;
    }
    final size = raw['size'];
    assets.add({
      'name': name,
      'browser_download_url': url,
      'urls': <String>{url, githubAssetUrl(tag, name)}.toList(),
      'size': size is int ? size : 0,
      'sha256': null,
    });
  }
  if (assets.isEmpty) {
    return null;
  }
  final body = data['body'];
  return {
    'tag_name': tag,
    'body': body is String ? body : null,
    'html_url': 'https://codeberg.org/$codebergRepository/releases/tag/$tag',
    'assets': assets,
  };
}

/// Adds the Codeberg copy of every asset as a further download candidate, so a
/// GitHub outage that starts after the check costs a retry rather than the
/// update. The payload from GitHub carries no `urls` of its own.
Map<String, dynamic> withStandbyAssets(Map<String, dynamic> release) {
  final tag = release['tag_name'];
  final assets = release['assets'];
  if (tag is! String || assets is! List) {
    return release;
  }
  for (final raw in assets) {
    if (raw is! Map) {
      continue;
    }
    final name = raw['name'];
    if (name is! String || name.isEmpty) {
      continue;
    }
    final declared = raw['browser_download_url'];
    final listed = raw['urls'];
    final urls = <String>{
      if (declared is String) declared,
      if (listed is List) ...listed.whereType<String>(),
      codebergAssetUrl(tag, name),
    }.where((url) => url.isNotEmpty).toList();
    raw['urls'] = urls;
  }
  return release;
}

/// Streams [path] through SHA-256 off the UI isolate; 60 MB of hashing would
/// otherwise land in a frame. Accepts the `sha256:` prefix some APIs write.
Future<bool> fileMatchesSha256(String path, String expected) {
  final wanted = expected.toLowerCase().replaceFirst('sha256:', '');
  if (wanted.isEmpty) {
    return Future.value(false);
  }
  return Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString() == wanted;
  });
}

/// Picks the asset for the running build out of a release payload.
///
/// Every platform names its asset `<app>-<version>-<os>-<arch>[-variant]`, so
/// the match works from the name alone rather than from the order the release
/// lists its assets in.
UpdateAsset? pickUpdateAsset(
  Map<String, dynamic> release, {
  TargetPlatform? platform,
  String? abi,
  bool installed = true,
}) {
  final assets = release['assets'];
  if (assets is! List) {
    return null;
  }
  final candidates = <UpdateAsset>[];
  for (final raw in assets) {
    if (raw is! Map) {
      continue;
    }
    final name = raw['name'];
    final url = raw['browser_download_url'];
    if (name is! String || url is! String) {
      continue;
    }
    final size = raw['size'];
    final listed = raw['urls'];
    // The declared URL leads, then any extra hosts; duplicates from a manifest
    // that lists the same host twice would only retry the same failure.
    final urls = <String>{
      url,
      if (listed is List) ...listed.whereType<String>(),
    }.where((item) => item.isNotEmpty).toList();
    final sha = raw['sha256'];
    // GitHub spells the same value `digest`, with the algorithm as a prefix.
    final digest = raw['digest'];
    final checksum = switch ((sha, digest)) {
      (final String value, _) when value.isNotEmpty => value,
      (_, final String value) when value.isNotEmpty => value,
      _ => null,
    };
    candidates.add((
      name: name,
      urls: urls,
      size: size is int ? size : 0,
      sha256: checksum,
    ));
  }
  return pickUpdateAssetFrom(
    candidates,
    platform: platform ?? defaultTargetPlatform,
    abi: abi ?? currentAbi,
    installed: installed,
  );
}

/// Null when this build has nothing it can install itself with: a portable copy
/// keeps pointing at the release page rather than unzipping over itself, and a
/// platform with no known installer gets no button.
@visibleForTesting
UpdateAsset? pickUpdateAssetFrom(
  List<UpdateAsset> candidates, {
  required TargetPlatform platform,
  required String abi,
  required bool installed,
}) {
  final platformTag = switch (platform) {
    TargetPlatform.windows => installed ? 'windows' : null,
    TargetPlatform.android => 'android',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    _ => null,
  };
  if (platformTag == null) {
    return null;
  }
  final arch = platform == TargetPlatform.android
      ? _androidArch(abi)
      : _desktopArch(abi);
  final suffix = switch (platform) {
    TargetPlatform.windows => '-setup.exe',
    TargetPlatform.android => '.apk',
    TargetPlatform.macOS => '.dmg',
    _ => '.AppImage',
  };
  for (final candidate in candidates) {
    if (!candidate.name.endsWith(suffix)) {
      continue;
    }
    final stem = candidate.name.substring(
      0,
      candidate.name.length - suffix.length,
    );
    // Matching the dashed stem keeps `-windows-amd64-setup.exe` from satisfying
    // `-windows-arm64-setup.exe`, whose tail carries the same characters.
    if (stem.endsWith('-$platformTag-$arch')) {
      return candidate;
    }
  }
  return null;
}

String _desktopArch(String abi) => abi == 'arm64' ? 'arm64' : 'amd64';

String _androidArch(String abi) => switch (abi) {
  'arm64' => 'arm64-v8a',
  'arm' => 'armeabi-v7a',
  _ => 'x86_64',
};

/// Dart's ABI for the running binary, spelled the way release assets spell it.
String get currentAbi {
  final abi = Abi.current();
  return switch (abi) {
    Abi.androidArm64 ||
    Abi.linuxArm64 ||
    Abi.macosArm64 ||
    Abi.windowsArm64 => 'arm64',
    Abi.androidArm || Abi.linuxArm => 'arm',
    _ => 'amd64',
  };
}

/// Inno Setup names its uninstaller `unins000.exe` and only an installed copy
/// has one; a portable unzip has no uninstaller to replace itself through.
@visibleForTesting
bool hasUninstaller(Iterable<String> fileNames) {
  return fileNames.any(
    (name) => name.startsWith('unins') && name.endsWith('.exe'),
  );
}

/// Whether this copy came from the Inno Setup installer, the only Windows
/// build an in-app update can replace. A portable unzip is offered the release
/// page instead of a second copy planted beside it.
Future<bool> isInstalledCopy() async {
  if (!Platform.isWindows) {
    return true;
  }
  try {
    final names = await Directory(
      dirname(Platform.resolvedExecutable),
    ).list().map((entity) => basename(entity.path)).toList();
    return hasUninstaller(names);
  } on FileSystemException {
    return false;
  }
}
