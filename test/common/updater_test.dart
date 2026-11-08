import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:gl_clash/common/constant.dart';
import 'package:gl_clash/common/updater.dart';
import 'package:gl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _release(List<String> names) => {
  'tag_name': 'v1.2.3',
  'assets': [
    for (final name in names)
      {
        'name': name,
        'browser_download_url':
            'https://github.com/$repository/releases/download/v1.2.3/$name',
        'size': 1024,
      },
  ],
};

const _allAssets = [
  'GLClash-1.2.3-android-arm64-v8a.apk',
  'GLClash-1.2.3-android-armeabi-v7a.apk',
  'GLClash-1.2.3-android-x86_64.apk',
  'GLClash-1.2.3-linux-amd64.AppImage',
  'GLClash-1.2.3-linux-arm64.AppImage',
  'GLClash-1.2.3-macos-amd64.dmg',
  'GLClash-1.2.3-macos-arm64.dmg',
  'GLClash-1.2.3-windows-amd64-setup.exe',
  'GLClash-1.2.3-windows-amd64.zip',
  'GLClash-1.2.3-windows-arm64-setup.exe',
  'GLClash-1.2.3-windows-arm64.zip',
];

void main() {
  group('rewriteUpdateUrl', () {
    test('leaves GitHub URLs alone on the official channel', () {
      const url = 'https://github.com/owner/repo/releases/download/v1/a.exe';

      expect(rewriteUpdateUrl(url, UpdateChannel.official), url);
    });

    test('prefixes GitHub URLs with each mirror on its channel', () {
      const url = 'https://github.com/owner/repo/releases/download/v1/a.exe';

      expect(
        rewriteUpdateUrl(url, UpdateChannel.mirror),
        '${updateMirrorPrefixes[UpdateChannel.mirror]}$url',
      );
      expect(
        rewriteUpdateUrl(url, UpdateChannel.mirrorOrg),
        '${updateMirrorPrefixes[UpdateChannel.mirrorOrg]}$url',
      );
      // The two mirrors must not collapse into one entry: a user picking the
      // other edge is picking a different prefix.
      expect(
        updateMirrorPrefixes[UpdateChannel.mirror],
        isNot(updateMirrorPrefixes[UpdateChannel.mirrorOrg]),
      );
    });

    test('leaves other hosts alone on the mirror channel', () {
      for (final url in [
        'https://example.com/a.exe',
        'https://cdn.github.com/a.exe',
        'https://dav.example.com/github.com/a.yaml',
      ]) {
        expect(rewriteUpdateUrl(url, UpdateChannel.mirror), url);
      }
    });

    test('leaves an unparsable URL alone rather than prefixing it', () {
      expect(rewriteUpdateUrl('', UpdateChannel.mirror), '');
    });

    test('routes both the API and the release page through the mirror', () {
      for (final channel in [UpdateChannel.mirror, UpdateChannel.mirrorOrg]) {
        final prefix = updateMirrorPrefixes[channel]!;
        expect(
          updateApiUrl(channel),
          '${prefix}https://api.github.com/repos/$repository/releases/latest',
        );
        expect(
          updateLatestPageUrl(channel),
          '${prefix}https://github.com/$repository/releases/latest',
        );
      }
    });
  });

  group('pickUpdateAsset', () {
    test('picks the installer matching each platform and architecture', () {
      final cases = <(TargetPlatform, String, String)>[
        (
          TargetPlatform.windows,
          'amd64',
          'GLClash-1.2.3-windows-amd64-setup.exe',
        ),
        (
          TargetPlatform.windows,
          'arm64',
          'GLClash-1.2.3-windows-arm64-setup.exe',
        ),
        (
          TargetPlatform.android,
          'arm64',
          'GLClash-1.2.3-android-arm64-v8a.apk',
        ),
        (
          TargetPlatform.android,
          'arm',
          'GLClash-1.2.3-android-armeabi-v7a.apk',
        ),
        (TargetPlatform.android, 'amd64', 'GLClash-1.2.3-android-x86_64.apk'),
        (TargetPlatform.macOS, 'amd64', 'GLClash-1.2.3-macos-amd64.dmg'),
        (TargetPlatform.macOS, 'arm64', 'GLClash-1.2.3-macos-arm64.dmg'),
        (TargetPlatform.linux, 'amd64', 'GLClash-1.2.3-linux-amd64.AppImage'),
        (TargetPlatform.linux, 'arm64', 'GLClash-1.2.3-linux-arm64.AppImage'),
      ];
      final release = _release(_allAssets);
      for (final (platform, abi, expected) in cases) {
        expect(
          pickUpdateAsset(release, platform: platform, abi: abi)?.name,
          expected,
          reason: '$platform/$abi',
        );
      }
    });

    test('does not let amd64 satisfy arm64', () {
      // `-windows-amd64-setup.exe` ends with the characters
      // `-windows-arm64-setup.exe` does once the leading dashes line up.
      final picked = pickUpdateAsset(
        _release(['GLClash-1.2.3-windows-amd64-setup.exe']),
        platform: TargetPlatform.windows,
        abi: 'arm64',
      );

      expect(picked, isNull);
    });

    test('refuses to unzip over a portable copy', () {
      final release = _release(_allAssets);

      expect(
        pickUpdateAsset(
          release,
          platform: TargetPlatform.windows,
          abi: 'amd64',
          installed: false,
        ),
        isNull,
      );
    });

    test('answers nothing for a platform it has no installer for', () {
      final release = _release(_allAssets);

      expect(
        pickUpdateAsset(release, platform: TargetPlatform.iOS, abi: 'arm64'),
        isNull,
      );
    });

    test('answers nothing when the release carries no matching asset', () {
      expect(
        pickUpdateAsset(
          _release(['GLClash-1.2.3-windows-amd64.zip']),
          platform: TargetPlatform.windows,
          abi: 'amd64',
        ),
        isNull,
      );
    });

    test('answers nothing for a payload without assets', () {
      expect(
        pickUpdateAsset(
          {'tag_name': 'v1.2.3'},
          platform: TargetPlatform.android,
          abi: 'arm64',
        ),
        isNull,
      );
      expect(
        pickUpdateAsset(
          {'tag_name': 'v1.2.3', 'assets': 'not a list'},
          platform: TargetPlatform.android,
          abi: 'arm64',
        ),
        isNull,
      );
    });

    test('skips malformed entries instead of throwing', () {
      final release = {
        'assets': [
          'not a map',
          {'name': 'x.exe'},
          {'browser_download_url': 'https://example.com/x.exe'},
          {
            'name': 'GLClash-1.2.3-android-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/a.apk',
            'size': 'not a number',
          },
        ],
      };

      final picked = pickUpdateAsset(
        release,
        platform: TargetPlatform.android,
        abi: 'arm64',
      );

      expect(picked?.name, 'GLClash-1.2.3-android-arm64-v8a.apk');
      expect(picked?.urls, ['https://example.com/a.apk']);
      expect(picked?.size, 0);
      expect(picked?.sha256, isNull);
    });
  });

  group('releaseFromCodeberg', () {
    test('maps tag, notes and assets onto the release shape', () {
      final release = releaseFromCodeberg({
        'tag_name': 'v1.2.3',
        'body': '- fixed a thing',
        'assets': [
          {
            'name': 'GLClash-1.2.3-windows-amd64-setup.exe',
            'size': 42,
            'browser_download_url':
                'https://codeberg.org/$codebergRepository/releases/download/'
                'v1.2.3/GLClash-1.2.3-windows-amd64-setup.exe',
          },
        ],
      });

      expect(release?['tag_name'], 'v1.2.3');
      expect(release?['body'], '- fixed a thing');
      final asset = (release?['assets'] as List).single as Map;
      expect(asset['browser_download_url'], contains('codeberg.org'));
      expect(asset['size'], 42);
      // Codeberg describes no digest per asset, so this release reports none and
      // the caller reads SHA256SUMS beside it instead.
      expect(asset['sha256'], isNull);
      // GitHub still carries the same file, so it becomes the second candidate.
      expect(
        asset['urls'],
        contains(
          'https://github.com/$repository/releases/download/'
          'v1.2.3/GLClash-1.2.3-windows-amd64-setup.exe',
        ),
      );
    });

    test('answers nothing for a payload without a tag or an asset', () {
      expect(releaseFromCodeberg(null), isNull);
      expect(releaseFromCodeberg('nope'), isNull);
      expect(releaseFromCodeberg({'body': 'x'}), isNull);
      expect(
        releaseFromCodeberg({'tag_name': 'v1.2.3', 'assets': <Object>[]}),
        isNull,
      );
    });

    test('drops an asset that carries no name or no url', () {
      final release = releaseFromCodeberg({
        'tag_name': 'v1.2.3',
        'assets': [
          {'name': 'no-url.apk'},
          {'browser_download_url': 'https://a'},
          {'name': 'no-size.apk', 'browser_download_url': 'https://b'},
          'not a map',
        ],
      });

      final asset = (release?['assets'] as List).single as Map;
      expect(asset['name'], 'no-size.apk');
      expect(asset['size'], 0);
    });
  });

  group('withStandbyAssets', () {
    test('appends the Codeberg copy to every GitHub asset', () {
      final release = withStandbyAssets({
        'tag_name': 'v1.2.3',
        'assets': [
          {
            'name': 'GLClash-1.2.3-android-arm64-v8a.apk',
            'browser_download_url':
                'https://github.com/$repository/releases/download/'
                'v1.2.3/GLClash-1.2.3-android-arm64-v8a.apk',
            'size': 7,
          },
        ],
      });

      expect((release['assets'] as List).single['urls'], [
        githubAssetUrl('v1.2.3', 'GLClash-1.2.3-android-arm64-v8a.apk'),
        codebergAssetUrl('v1.2.3', 'GLClash-1.2.3-android-arm64-v8a.apk'),
      ]);
    });

    test('leaves a payload without a tag or assets alone', () {
      expect(withStandbyAssets({'tag_name': 'v1.2.3'}), {'tag_name': 'v1.2.3'});
      expect(withStandbyAssets({'body': 'x'}), {'body': 'x'});
    });
  });

  group('parseSha256Sums', () {
    test('reads both sha256sum spacings and the BSD order', () {
      final sums = parseSha256Sums(
        '${'a' * 64}  GLClash-1.2.3-windows-amd64.zip\n'
        '${'B' * 64} *GLClash-1.2.3-windows-amd64-setup.exe\n'
        'SHA256 (GLClash-1.2.3-android-arm64-v8a.apk) = ${'c' * 64}\n'
        '\n'
        '# a comment\n'
        'not a checksum line\n',
      );

      expect(sums['GLClash-1.2.3-windows-amd64.zip'], 'a' * 64);
      // The binary form carries an asterisk before the name, and the digest is
      // normalized to lower case so a comparison against a manifest matches.
      expect(sums['GLClash-1.2.3-windows-amd64-setup.exe'], 'b' * 64);
      expect(sums['GLClash-1.2.3-android-arm64-v8a.apk'], 'c' * 64);
      expect(sums.length, 3);
    });

    test('answers nothing for text that carries no digest', () {
      expect(parseSha256Sums(''), isEmpty);
      expect(parseSha256Sums('abc  file\n'), isEmpty);
    });
  });

  group('fileMatchesSha256', () {
    test('accepts a matching digest and rejects a different one', () async {
      final file = File('${Directory.systemTemp.path}/glclash_sha_test.bin');
      await file.writeAsBytes(List<int>.generate(1024, (i) => i % 251));
      addTearDown(() async {
        if (await file.exists()) {
          await file.delete();
        }
      });

      final expected = sha256.convert(await file.readAsBytes()).toString();
      expect(await fileMatchesSha256(file.path, expected), isTrue);
      expect(await fileMatchesSha256(file.path, 'sha256:$expected'), isTrue);
      expect(await fileMatchesSha256(file.path, '0' * 64), isFalse);
      expect(await fileMatchesSha256(file.path, ''), isFalse);
    });
  });

  group('hasUninstaller', () {
    test('recognizes the Inno Setup uninstaller', () {
      expect(hasUninstaller(['GLClash.exe', 'unins000.exe']), isTrue);
      expect(hasUninstaller(['GLClash.exe', 'unins001.dat']), isFalse);
      expect(hasUninstaller(['GLClash.exe', 'GLClashCore.exe']), isFalse);
      expect(hasUninstaller(const []), isFalse);
    });
  });
}
