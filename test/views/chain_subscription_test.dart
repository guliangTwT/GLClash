import 'package:gl_clash/enum/enum.dart';
import 'package:gl_clash/models/models.dart';
import 'package:gl_clash/views/profiles/custom/dialers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chainsOf with a subscription upstream', () {
    test('a group carrying a subscription reads as the upstream', () {
      const exit = CustomProxy(
        id: 1,
        definition: {'name': 'Exit', 'type': 'socks5', 'server': '::1'},
      );
      // What picking a subscription creates.
      const carrier = ProxyGroup(
        id: 2,
        name: 'Nano · JP',
        type: GroupType.Selector,
        use: ['Nano'],
        filter: 'JP',
      );
      // The exit itself reaches the config through a group, as any proxy does.
      const main = ProxyGroup(
        id: 3,
        name: 'Main',
        type: GroupType.Selector,
        proxies: ['Exit'],
      );

      final chains = chainsOf(
        const [exit],
        const CustomProfileData(
          proxyGroups: [main, carrier],
          proxies: {'Exit'},
          dialers: {'Exit': 'Nano · JP'},
        ),
      );

      final chain = chains.single;
      expect(chain.exit.name, 'Exit');
      // The group is the upstream; its subscription nodes are the core's, so
      // the app can only name the group.
      expect(chain.upstream, isNull);
      expect(chain.upstreamGroup?.name, 'Nano · JP');
      expect(chain.upstreamGroup?.use, ['Nano']);
    });
  });
}
