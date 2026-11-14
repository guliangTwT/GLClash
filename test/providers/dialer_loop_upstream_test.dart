import 'package:gl_clash/enum/enum.dart';
import 'package:gl_clash/models/models.dart';
import 'package:gl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';

CustomProxy proxy(int id, String name) => CustomProxy(
  id: id,
  definition: {'name': name, 'type': 'socks5', 'server': '::1'},
);

ProxyGroup selector(int id, String name, List<String> proxies) =>
    ProxyGroup(id: id, name: name, type: GroupType.Selector, proxies: proxies);

void main() {
  group('an upstream no group names is still checked for loops', () {
    test('a self dial is dropped', () {
      // Hop exists only because a chain points at it: no group lists it.
      final hop = proxy(2, 'Hop');
      final payload = appProxiesPayload(
        [proxy(1, 'Exit'), hop],
        dialers: const {1: 'Hop', 2: 'Hop'},
        groups: [
          selector(3, 'Main', ['Exit']),
        ],
      );

      final byName = {for (final item in payload) item['name'] as String: item};
      // Hop dialing itself is a loop mihomo refuses the config for.
      expect(byName['Hop']!.containsKey('dialer-proxy'), isFalse);
      // Exit still reaches Hop, which is not a loop.
      expect(byName['Exit']!['dialer-proxy'], 'Hop');
    });

    test('two proxies dialing each other are both dropped', () {
      final payload = appProxiesPayload(
        [proxy(1, 'A'), proxy(2, 'B')],
        dialers: const {1: 'B', 2: 'A'},
        groups: [
          selector(3, 'Main', ['A']),
        ],
      );

      for (final item in payload) {
        expect(
          item.containsKey('dialer-proxy'),
          isFalse,
          reason: '${item['name']}',
        );
      }
    });

    test('a self dial is reported as an issue', () {
      final hop = proxy(2, 'Hop');
      const data = CustomProfileData(
        proxyGroups: [
          ProxyGroup(
            id: 3,
            name: 'Main',
            type: GroupType.Selector,
            proxies: ['Exit'],
          ),
        ],
        proxies: {'Exit', 'Hop'},
        dialers: {'Hop': 'Hop'},
      );

      expect(proxyDialerIssues(hop, 'Hop', data), [
        const CustomIssue.dialerLoop('Hop', 'Hop'),
      ]);
    });
  });
}
