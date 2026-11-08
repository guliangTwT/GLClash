import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get ua => [
    '$appName/v$version',
    'clash-verge',
    'Platform/${Platform.operatingSystem}',
  ].join(' ');
}

/// Compares two version strings the way release tags reach [checkForUpdate].
///
/// A prerelease sorts before the release it leads to (`0.9.3-pre.1` < `0.9.3`),
/// and a segment that is not a plain number counts as zero instead of throwing,
/// so a hand-written tag such as `v0.9.3-rc1` cannot break the update check.
int compareVersions(String version1, String version2) {
  final first = _Version.parse(version1);
  final second = _Version.parse(version2);
  final core = _compareNumbers(first.core, second.core);
  if (core != 0) {
    return core;
  }
  if (first.prerelease.isEmpty != second.prerelease.isEmpty) {
    return first.prerelease.isEmpty ? 1 : -1;
  }
  final pre = _comparePrerelease(first.prerelease, second.prerelease);
  if (pre != 0) {
    return pre;
  }
  return first.build.compareTo(second.build);
}

class _Version {
  const _Version(this.core, this.prerelease, this.build);

  factory _Version.parse(String version) {
    final text = version.trim().replaceFirst(_leadingV, '');
    final plus = text.indexOf('+');
    final head = plus < 0 ? text : text.substring(0, plus);
    final build = plus < 0 ? '' : text.substring(plus + 1);
    final dash = head.indexOf('-');
    final core = dash < 0 ? head : head.substring(0, dash);
    final prerelease = dash < 0 ? '' : head.substring(dash + 1);
    return _Version(
      core.split('.').map(_leadingNumber).toList(),
      prerelease.isEmpty ? const [] : prerelease.split('.'),
      _leadingNumber(build),
    );
  }

  final List<int> core;
  final List<String> prerelease;
  final int build;
}

final _leadingV = RegExp(r'^[vV]');
final _numberPrefix = RegExp(r'^\d+');

int _leadingNumber(String text) {
  final match = _numberPrefix.firstMatch(text);
  if (match == null) {
    return 0;
  }
  // A hand-written tag can carry a digit run past 2^63; int.parse throws on it,
  // and the update check must not fail over a build number nobody compares.
  final digits = match.group(0)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (digits.length > 18) {
    return _maxSafeVersionNumber;
  }
  return int.parse(digits);
}

const _maxSafeVersionNumber = 999999999999999999;

int _compareNumbers(List<int> left, List<int> right) {
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    final a = index < left.length ? left[index] : 0;
    final b = index < right.length ? right[index] : 0;
    if (a != b) {
      return a.compareTo(b);
    }
  }
  return 0;
}

int _comparePrerelease(List<String> left, List<String> right) {
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    if (index >= left.length) {
      return -1;
    }
    if (index >= right.length) {
      return 1;
    }
    final a = left[index];
    final b = right[index];
    final aNumber = int.tryParse(a);
    final bNumber = int.tryParse(b);
    final result = switch ((aNumber, bNumber)) {
      (final int x, final int y) => x.compareTo(y),
      (final int _, null) => -1,
      (null, final int _) => 1,
      _ => a.compareTo(b),
    };
    if (result != 0) {
      return result;
    }
  }
  return 0;
}

const releaseNotesBeginMarker = '<!-- glclash:changelog:begin -->';
const releaseNotesEndMarker = '<!-- glclash:changelog:end -->';

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
