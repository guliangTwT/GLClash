import 'package:gl_clash/enum/enum.dart';
import 'package:gl_clash/models/models.dart';
import 'package:gl_clash/providers/state.dart';
import 'package:gl_clash/views/profiles/custom/dialers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('an added chain reaches the config', () {
    test('an exit the profile carries is part of the payload', () {
      const exit = CustomProxy(
        id: 1,
        definition: {
          'name': 'Exit',
          'type': 'socks5',
          'server': '10.0.0.9',
          'port': 1080,
        },
      );
      // The group `_addToGroup` creates when the profile had none.
      const created = ProxyGroup(
        id: 2,
        name: 'Proxy',
        type: GroupType.Selector,
        proxies: ['Exit'],
      );

      final payload = appProxiesPayload(
        const [exit],
        dialers: const {},
        groups: const [created],
      );

      expect(payload.single['name'], 'Exit');
      expect(payload.single['server'], '10.0.0.9');
    });

    test('the chain reads back with its upstream', () {
      const exit = CustomProxy(
        id: 1,
        definition: {'name': 'Exit', 'type': 'socks5', 'server': '10.0.0.9'},
      );
      const hop = CustomProxy(
        id: 2,
        definition: {'name': 'Hop', 'type': 'http', 'server': '10.0.0.10'},
      );
      const group = ProxyGroup(
        id: 3,
        name: 'Proxy',
        type: GroupType.Selector,
        proxies: ['Exit'],
      );

      final chains = chainsOf(
        const [exit, hop],
        const CustomProfileData(
          proxyGroups: [group],
          proxies: {'Exit', 'Hop'},
          dialers: {'Exit': 'Hop'},
        ),
      );

      // Both are listed: Hop is an upstream, and the config has to declare it,
      // so it is also a possible exit once a chain points at it.
      final byName = {for (final chain in chains) chain.exit.name: chain};
      expect(byName.keys, {'Exit', 'Hop'});
      expect(byName['Exit']!.upstream?.name, 'Hop');
      expect(byName['Hop']!.upstream, isNull);
    });
  });
}
