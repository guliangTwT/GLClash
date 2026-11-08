part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;
  bool _isShowingUpdateNotice = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMonochromeTrayIcon() {
    ref
        .read(appSettingProvider.notifier)
        .update(
          (state) =>
              state.copyWith(monochromeTrayIcon: !state.monochromeTrayIcon),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    final setting = ref.read(appSettingProvider);
    if (!setting.autoCheckUpdate) return false;
    final Map<String, dynamic>? res;
    try {
      res = await request.checkForUpdate(channel: setting.updateChannel);
    } catch (error) {
      commonPrint.log(
        'checkForUpdate failed: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
    // A version the user skipped stays quiet on every later start; a newer one
    // replaces it and asks again.
    final tag = res?['tag_name'];
    if (tag is String && tag == setting.skippedUpdateVersion) {
      return false;
    }
    await checkUpdateResultHandle(data: res);
    return res != null;
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: AppTextStyle.title2.of(context),
      children: version == null
          ? [
              TextSpan(text: '\n', style: AppTextStyle.subheadline.of(context)),
              for (final submit in parseReleaseBody(body))
                TextSpan(
                  text: '- $submit \n',
                  style: AppTextStyle.subheadline.of(context),
                ),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(
                color: group.type == ChangelogType.breaking
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
              ),
        ),
        for (final entry in group.entries)
          TextSpan(
            text: '• ${entry.text}\n',
            style: AppTextStyle.subheadline.of(context),
          ),
      ],
    ];
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data == null) {
      if (isUser) {
        unawaited(
          dialogs.showAlert(
            title: currentAppLocalizations.checkUpdate,
            message: TextSpan(text: currentAppLocalizations.checkUpdateError),
          ),
        );
      }
      return;
    }
    // The startup check and a manual one can land together; the second would
    // stack an identical dialog on the first.
    if (_isShowingUpdateNotice) {
      return;
    }
    final context = globalState.navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final localizations = currentAppLocalizations;
    final tag = data['tag_name'] as String;
    // Only the payload is inspected here; whether this copy can replace itself
    // is a filesystem question that belongs in the click, not the dialog.
    final canInstallInApp = pickUpdateAsset(data) != null;
    late final bool? res;
    _isShowingUpdateNotice = true;
    try {
      res = await dialogs.showMessage(
        title: localizations.discoverNewVersion,
        message: _releaseSpan(context, tag, data['body'] as String?),
        confirmText: canInstallInApp
            ? localizations.updateNow
            : localizations.goDownload,
        cancelText: localizations.skipThisVersion,
      );
    } finally {
      _isShowingUpdateNotice = false;
    }
    if (res == true) {
      if (canInstallInApp) {
        unawaited(_downloadAndInstall(data));
      } else {
        unawaited(
          launchUrl(
            Uri.parse('https://github.com/$repository/releases/latest'),
          ),
        );
      }
    } else if (res == false) {
      // Skipping stays scoped to this release, whether the user reached it by
      // the automatic check or asked for it: the tag is remembered so the next
      // start goes quiet only while it is still the newest one.
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(skippedUpdateVersion: tag));
    }
  }

  Future<void> _downloadAndInstall(Map<String, dynamic> release) async {
    final navigatorContext = globalState.navigatorKey.currentContext;
    if (navigatorContext == null) {
      return;
    }
    final navigator = Navigator.of(navigatorContext);
    final action = ref.read(updateActionProvider.notifier);
    // Null until the server names a size: the bar animates as indeterminate
    // rather than sitting frozen at 0%, which reads as a stalled transfer.
    final progress = ValueNotifier<double?>(null);
    // The dialog's own route, captured so the teardown closes it rather than
    // whatever sits on top: a background failure can push its own alert during
    // a long transfer, and popping that instead would leave this dialog up
    // while [progress] is already disposed.
    Route<void>? dialogRoute;
    final dialogClosed = dialogs.showCommonDialog<void>(
      context: navigatorContext,
      dismissible: false,
      child: Builder(
        builder: (context) {
          dialogRoute = ModalRoute.of(context);
          return UpdateProgressDialog(
            progress: progress,
            onCancel: action.cancel,
          );
        },
      ),
    );
    UpdateOutcome outcome;
    try {
      outcome = await action.install(
        release,
        onProgress: (value) => progress.value = value,
      );
    } catch (error) {
      commonPrint.log(
        'install update failed: ${compactError(error)}',
        logLevel: LogLevel.error,
      );
      outcome = UpdateOutcome.failed;
    } finally {
      // The route keeps listening to [progress] through its exit animation, so
      // it goes first and the notifier is disposed only once that has finished.
      final route = dialogRoute;
      if (route != null && route.isActive) {
        navigator.removeRoute(route);
      }
      await dialogClosed;
      progress.dispose();
    }
    await _handleOutcome(outcome);
  }

  Future<void> _handleOutcome(UpdateOutcome outcome) async {
    final localizations = currentAppLocalizations;
    switch (outcome) {
      case UpdateOutcome.installing:
        // Android hands the APK to the system installer, which comes to the
        // foreground on its own. Windows runs the installer itself, which ends
        // this process; a declined elevation prompt leaves it open, so that
        // path still has something to say.
        if (system.isWindows) {
          await _exitAndInstall();
        }
      case UpdateOutcome.saved:
        dialogs.showNotifier(
          localizations.updateSaved,
          level: MessageLevel.success,
        );
      case UpdateOutcome.needsInstallPermission:
        dialogs.showNotifier(
          localizations.installPermissionTip,
          level: MessageLevel.warning,
        );
      case UpdateOutcome.cancelled:
        break;
      case UpdateOutcome.noAsset:
        dialogs.showNotifier(
          localizations.updateNoAsset,
          level: MessageLevel.warning,
        );
      case UpdateOutcome.portable:
        dialogs.showNotifier(
          localizations.updatePortableTip,
          level: MessageLevel.warning,
        );
      case UpdateOutcome.installFailed:
        dialogs.showNotifier(
          localizations.updateInstallStartFailed,
          level: MessageLevel.error,
        );
      case UpdateOutcome.failed:
        dialogs.showNotifier(
          localizations.updateFailed,
          level: MessageLevel.error,
        );
    }
  }

  Future<void> _exitAndInstall() async {
    final path = ref.read(updateActionProvider.notifier).takeInstallerPath();
    if (path == null) {
      return;
    }
    final started = await ref
        .read(systemActionProvider.notifier)
        .installUpdateAndExit(path);
    if (!started) {
      await _handleOutcome(UpdateOutcome.installFailed);
    }
  }
}
