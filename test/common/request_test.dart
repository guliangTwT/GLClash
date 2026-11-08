import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gl_clash/common/constant.dart';
import 'package:gl_clash/common/request.dart';
import 'package:gl_clash/common/updater.dart';
import 'package:gl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

class _StalledHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  String Function(Uri url)? findProxy;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;
}

class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.byHost, {this.byUrl = const {}});

  final Map<String, ResponseBody Function()> byHost;
  final Map<String, ResponseBody Function()> byUrl;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final byUrl = this.byUrl[options.uri.toString()];
    if (byUrl != null) {
      return byUrl();
    }
    return byHost[options.uri.host]!();
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  group('latestRelease', () {
    Request requestAnswering(
      Map<String, ResponseBody Function()> byHost, {
      Map<String, ResponseBody Function()> byUrl = const {},
    }) {
      return Request()
        ..dio.httpClientAdapter = _HostAdapter(byHost, byUrl: byUrl);
    }

    ResponseBody json(String body, [int status = 200]) =>
        ResponseBody.fromString(
          body,
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );

    ResponseBody codebergRelease(String tag) => json(
      '{"tag_name":"$tag","body":"- note","assets":'
      '[{"name":"GLClash-${tag.substring(1)}-windows-amd64-setup.exe",'
      '"size":7,"browser_download_url":'
      '"https://codeberg.org/$codebergRepository/releases/download/'
      '$tag/GLClash-${tag.substring(1)}-windows-amd64-setup.exe"},'
      '{"name":"$sha256SumsAssetName","size":100,"browser_download_url":'
      '"https://codeberg.org/$codebergRepository/releases/download/'
      '$tag/$sha256SumsAssetName"}]}',
    );

    test('reads the release from the GitHub API first', () async {
      final request = requestAnswering({
        'api.github.com': () => json('{"tag_name":"v1.2.3","body":"notes"}'),
      });

      expect(await request.latestRelease(), {
        'tag_name': 'v1.2.3',
        'body': 'notes',
      });
    });

    test('gives every GitHub asset a Codeberg copy as well', () async {
      final request = requestAnswering({
        'api.github.com': () => json(
          '{"tag_name":"v1.2.3","assets":[{"name":"GLClash-1.2.3-windows-amd64'
          '-setup.exe","size":7,"browser_download_url":'
          '"https://github.com/$repository/releases/download/v1.2.3/a.exe"}]}',
        ),
      });

      final release = await request.latestRelease();
      final asset = (release['assets'] as List).first as Map;

      expect(asset['urls'], [
        'https://github.com/$repository/releases/download/v1.2.3/a.exe',
        codebergAssetUrl('v1.2.3', 'GLClash-1.2.3-windows-amd64-setup.exe'),
      ]);
    });

    test('asks Codeberg when the GitHub API and page both fail', () async {
      final request = requestAnswering({
        'api.github.com': () => json('{}', 403),
        'github.com': () => ResponseBody.fromString('', 503),
        'codeberg.org': () => codebergRelease('v1.2.3'),
      });

      final release = await request.latestRelease();

      expect(release['tag_name'], 'v1.2.3');
      expect(release['html_url'], contains('codeberg.org'));
      expect((release['assets'] as List).length, 2);
    });

    test('reads the checksums beside a Codeberg release', () async {
      final digests = 'a' * 64;
      final request = requestAnswering(
        {
          'api.github.com': () => json('{}', 403),
          'github.com': () => ResponseBody.fromString('', 503),
          'codeberg.org': () => codebergRelease('v1.2.3'),
        },
        byUrl: {
          'https://codeberg.org/$codebergRepository/releases/download/'
              'v1.2.3/$sha256SumsAssetName': () => ResponseBody.fromString(
            '$digests  GLClash-1.2.3-windows-amd64-setup.exe\n',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          ),
        },
      );

      final release = await request.latestRelease();
      final asset = (release['assets'] as List).first as Map;

      // Without this the Codeberg copy could only be checked by size, which a
      // truncated transfer of the right length would pass.
      expect(asset['sha256'], digests);
    });

    test('answers the Codeberg release when SHA256SUMS is missing', () async {
      final request = requestAnswering(
        {
          'api.github.com': () => json('{}', 403),
          'github.com': () => ResponseBody.fromString('', 503),
          'codeberg.org': () => codebergRelease('v1.2.3'),
        },
        byUrl: {
          'https://codeberg.org/$codebergRepository/releases/download/'
              'v1.2.3/$sha256SumsAssetName': () =>
              ResponseBody.fromString('', 404),
        },
      );

      final release = await request.latestRelease();

      expect(release['tag_name'], 'v1.2.3');
    });

    test('surfaces the GitHub error when no source answers', () async {
      final request = requestAnswering({
        'api.github.com': () => json('{}', 403),
        'github.com': () => ResponseBody.fromString('', 503),
        'codeberg.org': () => ResponseBody.fromString('', 503),
      });

      await expectLater(request.latestRelease(), throwsA(isA<DioException>()));
    });

    test(
      'reads the release from the mirror when that channel is picked',
      () async {
        final request = Request()
          ..dio.httpClientAdapter = _HostAdapter({
            'gh-proxy.com': () => ResponseBody.fromString(
              '{"tag_name":"v1.2.3"}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            ),
          });

        expect(await request.latestRelease(channel: UpdateChannel.mirror), {
          'tag_name': 'v1.2.3',
        });
      },
    );

    test('reads the release from the API', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString(
          '{"tag_name":"v1.2.3","body":"notes"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      });

      expect(await request.latestRelease(), {
        'tag_name': 'v1.2.3',
        'body': 'notes',
      });
    });

    test(
      'falls back to the release page when the API is rate limited',
      () async {
        final request = requestAnswering({
          'api.github.com': () => ResponseBody.fromString('{}', 403),
          'github.com': () => ResponseBody.fromString(
            '',
            302,
            headers: {
              HttpHeaders.locationHeader: [
                'https://github.com/owner/repo/releases/tag/v1.2.4',
              ],
            },
          ),
        });

        expect(await request.latestRelease(), {'tag_name': 'v1.2.4'});
      },
    );

    test('falls back when the API answers an empty body', () async {
      final request = requestAnswering({
        'api.github.com': () => ResponseBody.fromString(
          '',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
        'github.com': () => ResponseBody.fromString(
          '',
          302,
          headers: {
            HttpHeaders.locationHeader: [
              'https://github.com/owner/repo/releases/tag/v1.2.5',
            ],
          },
        ),
      });

      expect(await request.latestRelease(), {'tag_name': 'v1.2.5'});
    });
  });

  group('checkForUpdate', () {
    test('falls back to the release page when the API omits the tag', () async {
      final request = Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => ResponseBody.fromString(
            '{"body":"notes"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
          'github.com': () => ResponseBody.fromString(
            '',
            302,
            headers: {
              HttpHeaders.locationHeader: [
                'https://github.com/owner/repo/releases/tag/v1.2.3',
              ],
            },
          ),
        });

      expect(await request.latestRelease(), {'tag_name': 'v1.2.3'});
    });

    test('rejects a release without a usable tag name', () async {
      final request = Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => ResponseBody.fromString(
            '{"body":"notes"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
          'github.com': () => ResponseBody.fromString(
            '',
            302,
            headers: {
              HttpHeaders.locationHeader: [
                'https://github.com/owner/repo/releases',
              ],
            },
          ),
        });

      await expectLater(
        request.checkForUpdate(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('downloadTarget', () {
    test('sends a URL without credentials unchanged', () {
      final target = downloadTarget('https://example.com/a.yaml?x=1');

      expect(target.uri.toString(), 'https://example.com/a.yaml?x=1');
      expect(target.headers, isEmpty);
    });

    test('moves decoded credentials into the Authorization header', () {
      for (final url in [
        'https://me@mail.com:p:w@dav.example.com/dav/a.yaml',
        'https://me%40mail.com:p%3Aw@dav.example.com/dav/a.yaml',
      ]) {
        final target = downloadTarget(url);

        expect(target.uri.toString(), 'https://dav.example.com/dav/a.yaml');
        expect(
          target.headers[HttpHeaders.authorizationHeader],
          'Basic ${base64.encode(utf8.encode('me@mail.com:p:w'))}',
        );
      }
    });
  });

  group('decompressUnlabeled', () {
    final yaml = utf8.encode('proxies: []\n');

    test('inflates a gzip or zlib body that arrived unlabeled', () {
      for (final codec in [gzip, zlib]) {
        final body = Uint8List.fromList(codec.encode(yaml));

        expect(decompressUnlabeled(body), yaml);
      }
    });

    test('leaves a plain body untouched', () {
      final body = Uint8List.fromList(yaml);

      expect(decompressUnlabeled(body), same(body));
    });

    test('keeps a body that only starts like gzip', () {
      final body = Uint8List.fromList([0x1f, 0x8b, 1, 2, 3]);

      expect(decompressUnlabeled(body), same(body));
    });
  });

  testWidgets('a stalled download fails at the shared download deadline', (
    tester,
  ) async {
    late final Future<Response<String>> pending;
    HttpOverrides.runZoned(() {
      pending = Request().getTextResponseForUrl('http://127.0.0.1/stalled');
    }, createHttpClient: (_) => _StalledHttpClient());
    var settled = false;
    final outcome = expectLater(
      pending.whenComplete(() => settled = true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    await tester.pump(downloadTimeoutDuration - const Duration(seconds: 1));
    expect(settled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await outcome;
  });
}
