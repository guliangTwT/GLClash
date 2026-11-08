import 'dart:io';

import 'package:gl_clash/common/common.dart';
import 'package:gl_clash/providers/action.dart';
import 'package:gl_clash/providers/app.dart';
import 'package:gl_clash/providers/config.dart';
import 'package:gl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';

const _runningVersion = '0.8.95';

const _payload =
    '{"schemaVersion":2,"versions":[{"version":"0.8.96","tag":"v0.8.96",'
    '"date":"2026-08-16","prerelease":false,"groups":['
    '{"type":"breaking","entries":[{"id":"af20769","text":'
    '"Re-import backups"}]},'
    '{"type":"feat","entries":[{"id":"1a2b3c4","text":'
    '"Override scripts"}]}]}]}';

const _bulletsOnly =
    '<!-- glclash:changelog:begin -->\n'
    '- Override scripts\n'
    '<!-- glclash:changelog:end -->\n';

String _bodyWith(String payload) =>
    '$_bulletsOnly\n<!-- glclash:changelog:json\n$payload\n-->\n';

Map<String, dynamic> release(String? body) => <String, dynamic>{
  'tag_name': 'v0.8.96',
  'body': body,
};

Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  Locale? locale,
  bool withStatusManager = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  // appSettingProvider is autoDispose; in the app `configProvider` keeps it
  // alive, so the test has to hold a listener or edits are dropped.
  container.listen(appSettingProvider, (_, _) {}, fireImmediately: true);
  container
      .read(viewSizeProvider.notifier)
      .update((_) => const Size(1200, 800));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        locale: locale,
        withStatusManager: withStatusManager,
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// The dialog blocks until the user answers, so tests must close it before
/// awaiting the call that opened it.
Future<void> tapCancel(WidgetTester tester) async {
  await tester.tap(find.byType(TextButton).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'GLClash',
      packageName: 'com.glclash.app',
      version: _runningVersion,
      buildNumber: '1',
    );
  });

  testWidgets('renders the grouped notes carried by the release', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();

    expect(find.textContaining('v0.8.96'), findsOneWidget);
    expect(find.textContaining('Re-import backups'), findsOneWidget);
    expect(find.textContaining('Override scripts'), findsOneWidget);
    expect(find.textContaining('Breaking changes'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('localizes the group titles but not the entries', (tester) async {
    final container = await pumpApp(tester, locale: const Locale('zh', 'CN'));

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();

    // Entry copy comes from the release payload and is English only; the group
    // headings still follow the app locale.
    expect(find.textContaining('新功能'), findsOneWidget);
    expect(find.textContaining('Override scripts'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('falls back to the bullets of a release without a payload', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: release(_bulletsOnly));
    await tester.pumpAndSettle();

    expect(find.textContaining('- Override scripts'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('a second notice does not stack on an open one', (tester) async {
    final container = await pumpApp(tester);

    final first = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();
    // The startup check and a manual one can answer at the same time; the
    // second call must return rather than push an identical dialog.
    final second = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();

    expect(find.text('Skip this version'), findsOneWidget);
    // One dialog means one pair of actions: a stacked copy would double these.
    expect(find.byType(TextButton), findsNWidgets(2));

    await tapCancel(tester);
    await first;
    await second;
  });

  testWidgets('skipping a release records it without disabling the check', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();

    expect(find.text('Skip this version'), findsOneWidget);

    await tapCancel(tester);
    await shown;

    final setting = container.read(appSettingProvider);
    expect(setting.skippedUpdateVersion, 'v0.8.96');
    expect(setting.autoCheckUpdate, isTrue);
  });

  testWidgets('a manual check keeps the setting and reports a failure', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(isUser: true);
    await tester.pumpAndSettle();

    expect(find.text('Check for updates'), findsOneWidget);

    await tapCancel(tester);
    await shown;
    expect(container.read(appSettingProvider).autoCheckUpdate, isTrue);
  });

  testWidgets('offers the in-app update when the release carries one', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    // Every installable asset, so the dialog finds one whichever platform the
    // test host reports.
    const names = [
      'GLClash-0.8.96-windows-amd64-setup.exe',
      'GLClash-0.8.96-windows-arm64-setup.exe',
      'GLClash-0.8.96-android-arm64-v8a.apk',
      'GLClash-0.8.96-android-armeabi-v7a.apk',
      'GLClash-0.8.96-android-x86_64.apk',
      'GLClash-0.8.96-macos-amd64.dmg',
      'GLClash-0.8.96-macos-arm64.dmg',
      'GLClash-0.8.96-linux-amd64.AppImage',
      'GLClash-0.8.96-linux-arm64.AppImage',
    ];

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(
          data: {
            ...release(_bodyWith(_payload)),
            'assets': [
              for (final name in names)
                {
                  'name': name,
                  'browser_download_url':
                      'https://github.com/GuLiang-I/GLClash/releases/download/'
                      'v0.8.96/$name',
                  'size': 1,
                },
            ],
          },
        );
    await tester.pumpAndSettle();

    expect(find.text('Update now'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('falls back to the release page without an installable asset', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    final shown = container
        .read(commonActionProvider.notifier)
        .checkUpdateResultHandle(data: release(_bodyWith(_payload)));
    await tester.pumpAndSettle();

    expect(find.text('Download'), findsOneWidget);

    await tapCancel(tester);
    await shown;
  });

  testWidgets('a failed download reports instead of vanishing', (tester) async {
    final container = await pumpApp(tester, withStatusManager: true);
    // Each platform resolves a different directory for the transfer (temp on
    // Windows, cache on Android, downloads elsewhere), and path_provider has no
    // implementation in a test VM, so all of them point at the temp directory.
    final previousTemporary = AppPath.temporaryDirectory;
    final previousCache = AppPath.cacheDirectory;
    final previousSupport = AppPath.supportDirectory;
    final previousDownloads = AppPath.downloadDirectory;
    AppPath.temporaryDirectory = () async => Directory.systemTemp;
    AppPath.cacheDirectory = () async => Directory.systemTemp;
    AppPath.supportDirectory = () async => Directory.systemTemp;
    AppPath.downloadDirectory = () async => Directory.systemTemp;
    addTearDown(() {
      AppPath.temporaryDirectory = previousTemporary;
      AppPath.cacheDirectory = previousCache;
      AppPath.supportDirectory = previousSupport;
      AppPath.downloadDirectory = previousDownloads;
    });

    final logged = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        logged.add(message);
      }
    };
    addTearDown(() => debugPrint = previousPrint);

    await tester.runAsync(() async {
      final shown = container
          .read(commonActionProvider.notifier)
          .checkUpdateResultHandle(
            data: {
              ...release(_bodyWith(_payload)),
              'assets': [
                // An unroutable scheme fails inside dio before a socket is
                // opened, so the failure arrives the same way on every host
                // instead of depending on how fast a refused port answers.
                for (final name in _installableNames)
                  {
                    'name': name,
                    'browser_download_url': 'nope://invalid/$name',
                    'size': 1,
                  },
              ],
            },
          );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update now'));
      // The progress bar animates as indeterminate until the server names a
      // size, so pumpAndSettle would never settle; a fixed pump suffices for
      // the dialog to open.
      await tester.pump(const Duration(milliseconds: 300));

      await shown;
      // The failed transfer resolves outside fake async, so poll until the
      // notice has gone through.
      for (var i = 0; i < 200; i++) {
        if (logged.any((line) => line.contains('message: Update failed'))) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump(const Duration(seconds: 1));

    // A failing transfer must reach the notice path: StatusManager logs every
    // message it shows, so its log line is the report the user would see.
    final reported = logged.any(
      (line) => line.contains('message: Update failed'),
    );
    debugPrint = previousPrint;
    expect(reported, isTrue);
  });
}

const _installableNames = [
  'GLClash-0.8.96-windows-amd64-setup.exe',
  'GLClash-0.8.96-windows-arm64-setup.exe',
  'GLClash-0.8.96-android-arm64-v8a.apk',
  'GLClash-0.8.96-android-armeabi-v7a.apk',
  'GLClash-0.8.96-android-x86_64.apk',
  'GLClash-0.8.96-macos-amd64.dmg',
  'GLClash-0.8.96-macos-arm64.dmg',
  'GLClash-0.8.96-linux-amd64.AppImage',
  'GLClash-0.8.96-linux-arm64.AppImage',
];
