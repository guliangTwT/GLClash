import 'package:gl_clash/features/form/upstream_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseUpstreamLine', () {
    test('reads host:port:user:pass', () {
      final parsed = parseUpstreamLine(
        'us.lajiaohttp.net:2000:asqfd30621-region-Random-sid-sPzradV3-t-5:'
        'cnbcqkhf',
      );

      expect(parsed?.server, 'us.lajiaohttp.net');
      expect(parsed?.port, 2000);
      expect(parsed?.username, 'asqfd30621-region-Random-sid-sPzradV3-t-5');
      expect(parsed?.password, 'cnbcqkhf');
      // The line names no scheme, so the form keeps its own kind.
      expect(parsed?.type, isNull);
    });

    test('a password holding colons keeps all of them', () {
      final parsed = parseUpstreamLine('h.example:1080:user:pa:ss:word');

      expect(parsed?.server, 'h.example');
      expect(parsed?.port, 1080);
      expect(parsed?.username, 'user');
      expect(parsed?.password, 'pa:ss:word');
    });

    test('reads host:port with no account', () {
      final parsed = parseUpstreamLine('1.2.3.4:8080');

      expect(parsed?.server, '1.2.3.4');
      expect(parsed?.port, 8080);
      expect(parsed?.username, '');
      expect(parsed?.password, '');
    });

    test('reads user:pass@host:port', () {
      final parsed = parseUpstreamLine('bob:s3cret@proxy.example:3128');

      expect(parsed?.server, 'proxy.example');
      expect(parsed?.port, 3128);
      expect(parsed?.username, 'bob');
      expect(parsed?.password, 's3cret');
    });

    test('reads a URL and takes the scheme as the type', () {
      final socks = parseUpstreamLine('socks5://u:p@10.0.0.9:1080');
      expect(socks?.type, 'socks5');
      expect(socks?.server, '10.0.0.9');
      expect(socks?.port, 1080);
      expect(socks?.username, 'u');
      expect(socks?.password, 'p');

      final http = parseUpstreamLine('http://10.0.0.9:7890/');
      expect(http?.type, 'http');
      expect(http?.server, '10.0.0.9');
      expect(http?.port, 7890);
      expect(http?.username, '');

      // socks5h resolves names on the proxy, which is still socks5 here.
      expect(parseUpstreamLine('socks5h://h:1')?.type, 'socks5');
    });

    test('reads an IPv6 host through its brackets', () {
      final parsed = parseUpstreamLine('[::1]:1080:u:p');

      expect(parsed?.server, '::1');
      expect(parsed?.port, 1080);
      expect(parsed?.username, 'u');
    });

    test('decodes a percent-encoded credential', () {
      final parsed = parseUpstreamLine('h.example:1:u%40x:p%3Aw');

      expect(parsed?.username, 'u@x');
      expect(parsed?.password, 'p:w');
    });

    test('a password holding @ keeps it in the four-part shape', () {
      // The host comes first, so its port ends the address; everything after
      // is the account, where '@' is just a character.
      final parsed = parseUpstreamLine('h.example:1080:user:pa@ss');

      expect(parsed?.server, 'h.example');
      expect(parsed?.port, 1080);
      expect(parsed?.username, 'user');
      expect(parsed?.password, 'pa@ss');
    });

    test('a password holding / ? # keeps them outside a URL', () {
      for (final password in ['pa/ss', 'pa?ss', 'pa#ss']) {
        final parsed = parseUpstreamLine('h.example:1080:user:$password');

        expect(parsed?.password, password, reason: password);
      }
    });

    test('a URL still drops its path', () {
      final parsed = parseUpstreamLine('http://h.example:7890/some/path');

      expect(parsed?.server, 'h.example');
      expect(parsed?.port, 7890);
      expect(parsed?.username, '');
    });

    test('an undecodable escape is kept as written', () {
      // A provider that encoded in GBK throws on decode; the raw text is what
      // the user has to paste back, not a crash.
      final parsed = parseUpstreamLine('h.example:1080:u%FF:p');

      expect(parsed, isNotNull);
      expect(parsed?.username, 'u%FF');
    });

    test('answers nothing for a line it cannot read', () {
      for (final line in [
        '',
        '   ',
        'just-a-host',
        'host:notaport',
        'host:0',
        'host:70000',
        '://x:1',
        'ftp://h:1',
        ':1080:u:p',
      ]) {
        expect(parseUpstreamLine(line), isNull, reason: line);
      }
    });

    test('a scheme the form cannot offer is refused, not guessed', () {
      // vmess and friends carry fields this form has no room for.
      expect(parseUpstreamLine('vmess://abc'), isNull);
      expect(parseUpstreamLine('ss://abc'), isNull);
    });
  });
}
