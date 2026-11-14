import 'package:gl_clash/common/common.dart';
import 'package:gl_clash/enum/enum.dart';
import 'package:gl_clash/features/form/form.dart';
import 'package:gl_clash/models/models.dart';
import 'package:gl_clash/providers/providers.dart';
import 'package:gl_clash/ui/icons/icons.dart';
import 'package:gl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The selection sheet's entries that open a form rather than naming a target.
/// Both carry a prefix no proxy or group can hold, so neither can collide with
/// a real name even when a subscription shares one.
const _manualUpstream = '\u0000manual-upstream';
const _subscriptionUpstreamPrefix = '\u0000subscription:';

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
          final groups = profileData?.proxyGroups ?? const <ProxyGroup>[];
          final loopOf = dialerLoopsOf(
            groups,
            proxy: proxy.name,
            dialers: profileData?.dialers ?? const {},
          );
          bool loops(String target) => loopOf(target).isNotEmpty;
          // Every local proxy is offered, not only the ones a group names: an
          // upstream may exist for no other reason, and the config declares it
          // because a chain points at it.
          final nodes = {
            for (final item
                in ref.watch(customProxiesProvider).value ??
                    const <CustomProxy>[])
              if (!loops(item.name)) item.name: proxyAddress(item),
          };
          final groupTypes = {
            for (final group in groups)
              if (!loops(group.name)) group.name: group.type.name,
          };
          // A subscription's nodes belong to the core, not to this profile, so
          // mihomo refuses to dial through one by name. A group carrying the
          // subscription is how a node of it becomes an upstream, which is what
          // picking a subscription here sets up.
          final subscriptions = {
            for (final MapEntry(key: label, value: _)
                in ref.watch(profileProvidersProvider).entries)
              if (!loops(label)) label: appLocalizations.chainSubscriptionNode,
          };
          return SelectionSheet<String>(
            title: appLocalizations.chainUpstream,
            sections: [
              SelectionSection(
                label: appLocalizations.chainUpstreamManual,
                items: const [_manualUpstream],
              ),
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
              SelectionSection(
                label: appLocalizations.chainSubscriptionUpstream,
                items: [
                  for (final label in subscriptions.keys)
                    '$_subscriptionUpstreamPrefix$label',
                ],
                subtitleBuilder: (_, item) =>
                    subscriptions[item.substring(
                      _subscriptionUpstreamPrefix.length,
                    )],
              ),
            ],
            labelBuilder: (item) => switch (item) {
              _manualUpstream => appLocalizations.chainUpstreamManual,
              '' => appLocalizations.chainDirect,
              _ when item.startsWith(_subscriptionUpstreamPrefix) =>
                item.substring(_subscriptionUpstreamPrefix.length),
              _ => item,
            },
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
    if (res == _manualUpstream) {
      if (!context.mounted) {
        return;
      }
      final title = context.appLocalizations.chainUpstreamManual;
      final upstream = await showUpstreamProxyForm(context, title: title);
      if (upstream == null) {
        return;
      }
      final name = _createUpstream(ref, upstream);
      ref.read(proxyDialersProvider(profileId).notifier).set(proxy.id, name);
      return;
    }
    if (res.startsWith(_subscriptionUpstreamPrefix)) {
      final subscription = res.substring(_subscriptionUpstreamPrefix.length);
      if (!ref.read(profileProvidersProvider).containsKey(subscription)) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      final filter = await showSubscriptionUpstreamForm(
        context,
        title: subscription,
      );
      if (filter == null || !context.mounted) {
        return;
      }
      // mihomo matches the filter as a regexp, so a typo there would otherwise
      // make the core refuse the whole config; ask it before saving.
      final errors = await checkFilters(ref, [filter]);
      if (!context.mounted) {
        return;
      }
      if (errors != null && errors.first.isNotEmpty) {
        await dialogs.showAlert(
          title: context.appLocalizations.cannotSave,
          message: TextSpan(
            text: context.appLocalizations.customIssueInvalidFilter(
              context.appLocalizations.chainSubscriptionFilter,
              errors.first,
            ),
          ),
        );
        return;
      }
      final name = _createSubscriptionUpstream(ref, subscription, filter);
      ref.read(proxyDialersProvider(profileId).notifier).set(proxy.id, name);
      return;
    }
    ref
        .read(proxyDialersProvider(profileId).notifier)
        .set(proxy.id, res.isEmpty ? null : res);
  }

  /// A group carrying [subscription], narrowed by [filter] when it names one,
  /// and answers the group's name.
  ///
  /// The chain has to point at something the config declares, and a
  /// subscription's nodes are the core's, so the group is what makes a node of
  /// it reachable as an upstream.
  String _createSubscriptionUpstream(
    WidgetRef ref,
    String subscription,
    String filter,
  ) {
    final taken = {
      for (final proxy
          in ref.read(customProxiesProvider).value ?? const <CustomProxy>[])
        proxy.name,
      for (final group
          in ref.read(proxyGroupsProvider(profileId)).value ??
              const <ProxyGroup>[])
        group.name,
      ...reservedCustomProxyNames,
    };
    final name = freeProxyName(
      filter.isEmpty ? subscription : '$subscription · $filter',
      taken,
    );
    ref
        .read(proxyGroupsProvider(profileId).notifier)
        .put(
          ProxyGroup(
            id: snowflake.id,
            name: name,
            type: GroupType.Selector,
            use: [subscription],
            filter: filter.isEmpty ? null : filter,
          ),
        );
    return name;
  }

  /// Saves the typed upstream as an app proxy and answers the name the chain
  /// points at, since a dialer has to name a proxy the config carries.
  String _createUpstream(WidgetRef ref, UpstreamProxy upstream) {
    final taken = {
      for (final proxy
          in ref.read(customProxiesProvider).value ?? const <CustomProxy>[])
        proxy.name,
      ...ref.read(customGroupNamesProvider).value ?? const <String>{},
      ...reservedCustomProxyNames,
    };
    final name = freeProxyName('${upstream.server}:${upstream.port}', taken);
    ref
        .read(customProxiesProvider.notifier)
        .put(
          CustomProxy.fromDefinition({
            'name': name,
            'type': upstream.type,
            'server': upstream.server,
            'port': upstream.port,
            if (upstream.username.isNotEmpty) 'username': upstream.username,
            if (upstream.password.isNotEmpty) 'password': upstream.password,
          }),
        );
    return name;
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
      iconActions: [
        IconButtonData(
          glyph: AppGlyphs.add,
          tooltip: appLocalizations.chainAdd,
          onPressed: () => _handleAdd(context, ref),
        ),
      ],
      body: NullStatusSwitcher(
        isLoading: chains == null,
        isEmpty: chains?.isEmpty ?? true,
        isSearching: false,
        nullStatus: NullStatus(
          label: appLocalizations.chainEmpty,
          illustration: NullStatusIllustration.proxies,
          action: TonalButton(
            size: TonalButtonSize.bar,
            glyph: AppGlyphs.addCircle,
            label: appLocalizations.chainAdd,
            onPressed: () => _handleAdd(context, ref),
          ),
        ),
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

  /// Adds a chain: the exit is a proxy this profile carries, so a new one is
  /// created from the same short form an upstream uses, then its upstream is
  /// picked through the usual sheet.
  Future<void> _handleAdd(BuildContext context, WidgetRef ref) async {
    final title = context.appLocalizations.chainExitAddress;
    final exit = await showUpstreamProxyForm(context, title: title);
    if (exit == null || !context.mounted) {
      return;
    }
    final name = _createUpstream(ref, exit);
    _addToGroup(ref, name);
    final proxy =
        (ref.read(customProxiesProvider).value ?? const <CustomProxy>[])
            .firstWhere((item) => item.name == name);
    if (!context.mounted) {
      return;
    }
    await _handleSelect(context, ref, proxy);
  }

  /// Puts a new proxy into a group, since a config declares one only when a
  /// group takes it in; a profile with no group gets one holding just this
  /// proxy, or the chain would have nothing to route through.
  void _addToGroup(WidgetRef ref, String name) {
    final groups = ref.read(proxyGroupsProvider(profileId)).value;
    final notifier = ref.read(proxyGroupsProvider(profileId).notifier);
    final selector = groups?.where((group) {
      return group.type == GroupType.Selector;
    }).firstOrNull;
    if (selector != null) {
      notifier.put(selector.copyWith(proxies: [...?selector.proxies, name]));
      return;
    }
    if (groups != null && groups.isNotEmpty) {
      final target = groups.first;
      notifier.put(target.copyWith(proxies: [...?target.proxies, name]));
      return;
    }
    final taken = {
      for (final proxy
          in ref.read(customProxiesProvider).value ?? const <CustomProxy>[])
        proxy.name,
      ...?groups?.map((group) => group.name),
      ...reservedCustomProxyNames,
    };
    notifier.put(
      ProxyGroup(
        id: snowflake.id,
        name: freeProxyName('Proxy', taken),
        type: GroupType.Selector,
        proxies: [name],
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
