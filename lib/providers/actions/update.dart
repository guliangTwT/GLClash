part of '../action.dart';

/// Reports 0..1, or null while the server has not said how large the file is.
typedef UpdateProgress = void Function(double? value);

@Riverpod(keepAlive: true)
class UpdateAction extends _$UpdateAction {
  CancelToken? _cancelToken;
  String? _installerPath;

  @override
  void build() {}

  UpdateChannel get _channel => ref.read(appSettingProvider).updateChannel;

  void cancel() {
    _cancelToken?.cancel('cancelled by the user');
  }

  /// Downloads the release asset for this build and hands it to the platform.
  Future<UpdateOutcome> install(
    Map<String, dynamic> release, {
    UpdateProgress? onProgress,
  }) async {
    final installed = await isInstalledCopy();
    final asset = pickUpdateAsset(release, installed: installed);
    if (asset == null) {
      // A portable Windows copy is the one case where the release does carry an
      // installer but this copy cannot use it, and saying "no installer" there
      // would send the user looking for a file that has always been there.
      return !installed && system.isWindows
          ? UpdateOutcome.portable
          : UpdateOutcome.noAsset;
    }
    if (system.isAndroid) {
      return _installAndroid(asset, onProgress: onProgress);
    }
    if (system.isWindows) {
      return _installWindows(asset, onProgress: onProgress);
    }
    return _saveForUser(asset, onProgress: onProgress);
  }

  Future<UpdateOutcome> _installWindows(
    UpdateAsset asset, {
    UpdateProgress? onProgress,
  }) async {
    final path = await _download(
      asset,
      join(await appPath.tempPath, _updateDirName),
      onProgress: onProgress,
    );
    if (path == null) {
      return UpdateOutcome.cancelled;
    }
    // The installer replaces the executables this process holds open and raises
    // its own elevation prompt. Handing the path back lets the caller close the
    // app first: Inno's KillProcesses would otherwise force it away mid-write,
    // taking any unsaved state with it.
    _installerPath = path;
    return UpdateOutcome.installing;
  }

  /// The downloaded installer, for the caller to run once the app is closed.
  String? takeInstallerPath() {
    final path = _installerPath;
    _installerPath = null;
    return path;
  }

  Future<UpdateOutcome> _installAndroid(
    UpdateAsset asset, {
    UpdateProgress? onProgress,
  }) async {
    final cacheDir = await appPath.cacheDir.future;
    final path = await _download(
      asset,
      join(cacheDir.path, _updateDirName),
      onProgress: onProgress,
    );
    if (path == null) {
      return UpdateOutcome.cancelled;
    }
    final plugin = app;
    if (plugin == null) {
      return UpdateOutcome.failed;
    }
    if (!await plugin.canRequestPackageInstalls()) {
      await plugin.openInstallPermissionSettings();
      return UpdateOutcome.needsInstallPermission;
    }
    return await plugin.installApk(path)
        ? UpdateOutcome.installing
        : UpdateOutcome.failed;
  }

  /// macOS and Linux ship no installer this app can drive, so the file is
  /// saved where the user can run it instead of being launched unattended.
  Future<UpdateOutcome> _saveForUser(
    UpdateAsset asset, {
    UpdateProgress? onProgress,
  }) async {
    final downloads = await appPath.downloadDirPath;
    final path = await _download(
      asset,
      join(downloads, _updateDirName),
      onProgress: onProgress,
    );
    return path == null ? UpdateOutcome.cancelled : UpdateOutcome.saved;
  }

  /// Null when the transfer was cancelled.
  ///
  /// An already-complete file short-circuits the transfer: the Android
  /// permission detour sends the user back through here, and re-downloading a
  /// 60 MB APK for a grant that took one tap would read as the update failing.
  /// The short-circuit still verifies the checksum first, so a truncated or
  /// corrupted leftover is replaced rather than installed.
  Future<String?> _download(
    UpdateAsset asset,
    String dirPath, {
    UpdateProgress? onProgress,
  }) async {
    cancel();
    final token = CancelToken();
    _cancelToken = token;
    final savePath = join(dirPath, asset.name);
    try {
      await Directory(dirPath).create(recursive: true);
      final existing = File(savePath);
      if (asset.size > 0 && await existing.exists()) {
        final complete = (await existing.length()) == asset.size;
        if (complete && await _matches(asset, savePath)) {
          onProgress?.call(1);
          return savePath;
        }
        await existing.safeDelete();
      }
      for (final url in asset.urls) {
        if (token.isCancelled) {
          return null;
        }
        bool completed;
        try {
          completed = await request.downloadFile(
            url: url,
            savePath: savePath,
            channel: _channel,
            cancelToken: token,
            onReceiveProgress: (received, total) {
              onProgress?.call(total > 0 ? received / total : null);
            },
          );
        } on Object catch (error) {
          // One unreachable host must not end the attempt while another still
          // lists the same file.
          await File(savePath).safeDelete();
          commonPrint.log(
            'update download from $url failed: ${compactError(error)}',
            logLevel: LogLevel.warning,
          );
          continue;
        }
        if (!completed) {
          await File(savePath).safeDelete();
          return null;
        }
        if (await _matches(asset, savePath)) {
          return savePath;
        }
        // A mirror that served a damaged or stale file is not a reason to give
        // up either: drop it and try the next host.
        await File(savePath).safeDelete();
        commonPrint.log(
          'checksum mismatch from $url, trying the next host',
          logLevel: LogLevel.warning,
        );
      }
      throw StateError('Update asset could not be fetched from any host');
    } finally {
      if (identical(_cancelToken, token)) {
        _cancelToken = null;
      }
    }
  }

  /// True when the payload declares no checksum, or the file matches it.
  Future<bool> _matches(UpdateAsset asset, String path) async {
    final expected = asset.sha256;
    if (expected == null) {
      return true;
    }
    return fileMatchesSha256(path, expected);
  }
}

enum UpdateOutcome {
  /// The installer is running; the app should quit so it can replace the files.
  installing,

  /// Saved where the user can run it, without being launched.
  saved,

  /// Android needs the one-time unknown-sources grant before it will install.
  needsInstallPermission,

  cancelled,

  /// The release carried no asset this build can install itself with.
  noAsset,

  /// This is a portable Windows copy, which the installer cannot overwrite.
  portable,

  /// The installer could not be started, so the app stayed open.
  installFailed,

  failed,
}

const _updateDirName = 'updates';
