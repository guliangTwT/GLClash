import 'package:gl_clash/common/common.dart';
import 'package:gl_clash/features/form/form.dart';
import 'package:gl_clash/models/models.dart';
import 'package:gl_clash/providers/providers.dart';
import 'package:gl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A proxy's chain, read as the two addresses that decide where its traffic
/// leaves from: the exit this profile names, and the upstream that carries it.
///
/// mihomo calls the upstream `dialer-proxy`: the proxy asks that target to open
/// the connection for it. Chains are independent of one another, so a profile
/// can run several at once, and an upstream naming a group ends the chain the
/// app can draw because the core picks the member at dial time.
class CustomProxyDialersView extends ConsumerWidget {
  final int profileId;

  const CustomProxyDialersView(this.profileId, {super.key});

  Future<void> _handleSelect(
    BuildContext context,
    WidgetRef ref,
    CustomProxy proxy,
  ) async {
    final res = await showSheet<String>(
      context: context,
      builder: (context) => Consumer(
        builder: (_, ref, _) {
          final appLocalizations = context.appLocalizations;
          final profileData = ref.watch(customProfileDataProvider(profileId));
          final named = profileData?.namedProxies ?? const <String>{};
          final groups = profileData?.proxyGroups ?? const <ProxyGroup>[];
          final loopOf = dialerLoopsOf(
            groups,
            proxy: proxy.name,
            dialers: profileData?.dialers ?? const {},
          );
          bool loops(String target) => loopOf(target).isNotEmpty;
          final nodes = {
            for (final item
                in ref.watch(customProxiesProvider).value ??
                    const <CustomProxy>[])
              if (named.contains(item.name) && !loops(item.name))
                item.name: proxyAddress(item),
          };
          final groupTypes = {
            for (final group in groups)
              if (!loops(group.name)) group.name: group.type.name,
          };
          return SelectionSheet<String>(
            title: appLocalizations.chainUpstream,
            sections: [
              SelectionSection(
                label: appLocalizations.chainNoUpstream,
                items: const [''],
              ),
              SelectionSection(
                label: appLocalizations.localProxies,
                items: nodes.keys.toList(),
                subtitleBuilder: (_, name) => nodes[name],
              ),
              SelectionSection(
                label: appLocalizations.proxyGroup,
                items: groupTypes.keys.toList(),
                subtitleBuilder: (_, name) => groupTypes[name],
              ),
            ],
            labelBuilder: (item) =>
                item.isEmpty ? appLocalizations.chainDirect : item,
            selectedOf: (ref) => ref.watch(
              proxyDialersProvider(
                profileId,
              ).select((state) => state.value?[proxy.id] ?? ''),
            ),
            onSelected: (item) => Navigator.of(context).pop(item),
          );
        },
      ),
    );
    if (res == null) {
      return;
    }
    ref
        .read(proxyDialersProvider(profileId).notifier)
        .set(proxy.id, res.isEmpty ? null : res);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final data = ref.watch(customProfileDataProvider(profileId));
    final all = ref.watch(customProxiesProvider).value;
    // Watched here so the page keeps the dialers alive between opening a sheet
    // and saving into it, and so a change made elsewhere redraws the chains.
    ref.watch(proxyDialersProvider(profileId));
    final chains = data == null || all == null ? null : chainsOf(all, data);
    return CommonScaffold(
      title: appLocalizations.chainProxy,
      body: NullStatusSwitcher(
        isLoading: chains == null,
        isEmpty: chains?.isEmpty ?? true,
        isSearching: false,
        nullStatus: NullStatus(label: appLocalizations.appProxiesEmpty),
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding,
            16,
            24 + context.bottomInset,
          ),
          itemCount: chains?.length ?? 0,
          itemBuilder: (_, index) {
            final chain = chains![index];
            return ItemPositionProvider(
              key: ValueKey(chain.exit.id),
              position: ItemPosition.get(index, chains.length),
              child: _ChainItem(
                profileId: profileId,
                chain: chain,
                onPressed: () => _handleSelect(context, ref, chain.exit),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The address a proxy connects to, which is what tells two similarly named
/// nodes apart.
String proxyAddress(CustomProxy proxy) {
  final server = proxy.server;
  final port = proxy.port;
  if (server == null || server.isEmpty) {
    return proxy.type;
  }
  return port == null ? server : '$server:$port';
}

/// One proxy and the upstream its connection goes through.
///
/// [upstream] is null when the proxy leaves directly. [upstreamGroup] is set
/// instead when the upstream is a group, whose member the core picks at dial
/// time; that ends the chain as far as the app can say.
typedef Chain = ({
  CustomProxy exit,
  CustomProxy? upstream,
  ProxyGroup? upstreamGroup,
});

/// A chain per proxy a group names, which is the set the config declares.
///
/// A name two proxies share is listed once: the core declares one of them, and
/// the edit lives on that proxy's id.
List<Chain> chainsOf(Iterable<CustomProxy> proxies, CustomProfileData data) {
  final byName = <String, CustomProxy>{};
  for (final proxy in proxies) {
    byName.putIfAbsent(proxy.name, () => proxy);
  }
  final firstIds = {for (final proxy in byName.values) proxy.id};
  final groups = {for (final group in data.proxyGroups) group.name: group};
  return [
    for (final exit in proxies)
      if (firstIds.contains(exit.id) && data.namedProxies.contains(exit.name))
        (
          exit: exit,
          upstream: byName[data.dialers[exit.name]],
          upstreamGroup: groups[data.dialers[exit.name]],
        ),
  ];
}

class _ChainItem extends ConsumerWidget {
  final int profileId;
  final Chain chain;
  final VoidCallback onPressed;

  const _ChainItem({
    required this.profileId,
    required this.chain,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final issues = ref
        .watch(
          customProfileIssuesProvider(profileId).select(
            (state) => SelectValue(
              state.dialers[chain.exit.id] ?? const <CustomIssue>[],
            ),
          ),
        )
        .value;
    final upstream = chain.upstream;
    final upstreamGroup = chain.upstreamGroup;
    return DecorationListItem(
      invalid: issues.isNotEmpty,
      onPressed: onPressed,
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      title: _AddressRow(
        label: appLocalizations.chainExitAddress,
        value: chain.exit.name,
        detail: proxyAddress(chain.exit),
      ),
      subtitle: _AddressRow(
        label: appLocalizations.chainUpstreamAddress,
        value:
            upstream?.name ??
            upstreamGroup?.name ??
            appLocalizations.chainDirect,
        detail: upstream == null
            ? upstreamGroup?.type.name
            : proxyAddress(upstream),
      ),
      trailing: issues.isEmpty ? null : CustomIssueButton(issues: issues),
    );
  }
}

/// A labelled value, so both addresses line up down the list and the row reads
/// as a pair rather than as a title with a subtitle.
class _AddressRow extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;

  const _AddressRow({required this.label, required this.value, this.detail});

  @override
  Widget build(BuildContext context) {
    final detailStyle = AppTextStyle.footnote
        .of(context)
        .copyWith(color: context.colorScheme.onSurfaceVariant);
    return Row(
      children: [
        Text(label, style: detailStyle),
        const SizedBox(width: 10),
        Expanded(
          child: TooltipText(
            text: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (detail != null)
          Flexible(
            child: Text(
              '· $detail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: detailStyle,
            ),
          ),
      ],
    );
  }
}
