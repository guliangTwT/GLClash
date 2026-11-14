import 'package:gl_clash/enum/enum.dart';
import 'package:gl_clash/models/models.dart';
import 'package:gl_clash/views/profiles/custom/dialers.dart';
import 'package:flutter_test/flutter_test.dart';

CustomProxy proxy(int id, String name, {String? server, int? port}) =>
    CustomProxy(
      id: id,
      definition: {
        'name': name,
        'type': 'socks5',
        'server': ?server,
        'port': ?port,
      },
    );

ProxyGroup selector(int id, String name, List<String> proxies) =>
    ProxyGroup(id: id, name: name, type: GroupType.Selector, proxies: proxies);

void main() {
  group('chainsOf', () {
    test('reads each named proxy as exit and its dialer as upstream', () {
      final home = proxy(1, 'Home', server: '10.0.0.1', port: 1080);
      final relay = proxy(2, 'Relay', server: '10.0.0.2', port: 1081);
      final spare = proxy(3, 'Spare', server: '10.0.0.3', port: 1082);

      final chains = chainsOf(
        [home, relay, spare],
        CustomProfileData(
          proxyGroups: [
            selector(1, 'Sel', ['Home', 'Relay']),
          ],
          proxies: {'Home', 'Relay', 'Spare'},
          dialers: const {'Home': 'Relay'},
        ),
      );

      // Spare is named by no group, so the config never declares it.
      expect(chains.map((chain) => chain.exit.name), ['Home', 'Relay']);
      final homeChain = chains.first;
      expect((homeChain.upstream?.name), 'Relay');
      expect(homeChain.upstreamGroup, isNull);
      // Relay leaves directly: no upstream, and the row shows that as 鐩磋繛.
      expect(chains.last.upstream, isNull);
      expect(chains.last.upstreamGroup, isNull);
    });

    test('carries the group a dialer names', () {
      final home = proxy(1, 'Home');
      final chain = chainsOf(
        [home],
        CustomProfileData(
          proxyGroups: [
            selector(1, 'Sel', ['Home']),
            selector(2, 'Hop', ['DIRECT']),
          ],
          proxies: {'Home'},
          dialers: const {'Home': 'Hop'},
        ),
      ).single;

      expect(chain.upstream, isNull);
      expect(chain.upstreamGroup?.name, 'Hop');
    });

    test('shows the address a proxy connects to', () {
      expect(
        proxyAddress(proxy(1, 'Home', server: '10.0.0.1', port: 1080)),
        '10.0.0.1:1080',
      );
      // A proxy with no port, or no server, falls back to what it does have.
      expect(proxyAddress(proxy(2, 'a', server: 'example.com')), 'example.com');
      expect(proxyAddress(proxy(3, 'b')), 'socks5');
    });

    test('a duplicate name does not become two exits', () {
      final home = proxy(1, 'Home');
      final chains = chainsOf(
        [home, proxy(2, 'Home')],
        CustomProfileData(
          proxyGroups: [
            selector(1, 'Sel', ['Home']),
          ],
          proxies: {'Home'},
        ),
      );

      expect(chains, hasLength(1));
      expect(chains.single.exit.id, 1);
    });
  });
}
