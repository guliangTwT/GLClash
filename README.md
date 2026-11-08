<div align="center">

<img src="assets/images/icon.png" alt="GLClash" width="88">

# GLClash

A multi-platform proxy client built on mihomo (Clash.Meta): simple, open source, ad-free.

**English** · [简体中文](README_zh_CN.md)

[![Release](https://img.shields.io/github/v/release/guliangTwT/GLClash?style=flat-square&label=release)](https://github.com/guliangTwT/GLClash/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/guliangTwT/GLClash/total?style=flat-square&logo=github)](https://github.com/guliangTwT/GLClash/releases)
[![License](https://img.shields.io/github/license/guliangTwT/GLClash?style=flat-square)](LICENSE)

[Download](#download) · [Changelog](CHANGELOG.md) · [Build from source](#build-from-source) · [Credits](#credits)

</div>

## About

GLClash is a renamed distribution of [FlClash](https://github.com/chen08209/FlClash). The app name, icon names,
the Android application id (`com.glclash.app`), the Windows and Linux executables, the core and Helper service names
(`GLClashCore`, `GLClashHelperService`), the URL scheme (`glclash://`) and all user-facing strings now say GLClash.
A few update-check and packaging defects were fixed along the way; see [CHANGELOG.md](CHANGELOG.md).

The core is still mihomo (Clash.Meta), so protocols and configuration files stay compatible with the Clash
ecosystem. GLClash keeps **its own data directory**, so it can be installed next to FlClash without sharing profiles:

| Platform | GLClash data directory |
| --- | --- |
| Windows | `%APPDATA%\GuLiang-I\GLClash` |
| Android | the app-private directory of `com.glclash.app` |
| macOS / Linux | `com.glclash.app`, by bundle/application id |

## Features

- **One app for Android, Windows, macOS and Linux**, with x64 and ARM64 desktop builds.
- **mihomo core**: rule-based routing, proxy groups, delay tests, system proxy and TUN mode.
- **Profile management**: import by subscription URL or file, in-app editor, override scripts, custom rules,
  proxies and groups.
- **Live views** for connections, requests, DNS queries and logs.
- **Material You with Apple-style interactions**: dynamic color, light and dark themes, superellipse corners,
  height-snapping sheets, layouts from phone to desktop.
- **Backup and restore** through WebDAV or local files.
- **Platform details**: Android quick-settings tile, per-app proxy and Android TV support; desktop tray menu and
  global shortcuts.
- **Open source and ad-free**, released under GPL-3.0.

## Download

Download only from [GitHub Releases](https://github.com/guliangTwT/GLClash/releases/latest), with a
[Codeberg mirror](https://codeberg.org/GuLiang/GLClash/releases/latest) of every release. The current release ships:

| Platform | Installer | Notes |
| --- | --- | --- |
| Android | `GLClash-<version>-android-arm64-v8a.apk` | Right pick for most phones; `armeabi-v7a` and `x86_64` are also published. |
| Windows 10+ | `GLClash-<version>-windows-amd64-setup.exe` | Inno Setup installer; a portable `.zip` is published alongside. |

ARM64 desktop builds, macOS DMGs and the Linux deb/rpm/AppImage need their own host toolchains and are not produced by
this repository's release flow yet; see [Build from source](#build-from-source).

## Usage

**Import a profile from a link.** Opening a link in the format below imports the subscription; `clashmeta://` and
`glclash://` links work as well.

```text
clash://install-config?url=<percent-encoded subscription URL>
```

**Android automation.** Tasker, MacroDroid and friends can start, stop or toggle the proxy through these actions:

```text
com.glclash.app.action.START
com.glclash.app.action.STOP
com.glclash.app.action.TOGGLE
```

From a computer:

```bash
adb shell am start -a com.glclash.app.action.TOGGLE
```

**Headless desktops.** The core starts only after the disclaimer is accepted. In containers, set
`GLCLASH_ACCEPT_DISCLAIMER=1` to accept it on first launch.

## Build from source

Requires [Flutter](https://docs.flutter.dev/get-started/install) 3.47 (release builds pin 3.47.6),
[Go](https://go.dev/dl/) 1.27 and [Rust](https://rustup.rs/).

```bash
git clone --recursive https://github.com/guliangTwT/GLClash.git
cd GLClash
flutter pub get
dart setup.dart windows   # or android, macos, linux
```

Packages land in `dist/`; the Go core and the Rust library are built by Flutter's build hook into `libclash/`.

| Platform | Extra requirements |
| --- | --- |
| Android | Android SDK with NDK and JDK 17+. `--arch arm64` builds a single ABI. |
| Windows | Visual Studio 2022 "Desktop development with C++", plus [Inno Setup](https://jrsoftware.org/isinfo.php) 6. |
| macOS | Xcode and Node.js (the script installs `appdmg` through npm). |
| Linux | Debian or Ubuntu; the script apt-installs its packages and fetches `appimagetool`. |

`dart setup.dart --help` lists the remaining options, such as `--targets` to build only some package formats.

> `core/Clash.Meta` is a submodule: clone with `--recursive`, or run `git submodule update --init --recursive`.

## Credits

- [FlClash](https://github.com/chen08209/FlClash): the UI, architecture and build pipeline this project derives from.
  Thanks to chen08209 and its contributors.
- [mihomo / Clash.Meta](https://github.com/MetaCubeX/mihomo): the proxy core.
- Every open-source project and translator FlClash builds on.

As GPL-3.0 requires, the original [LICENSE](LICENSE) and the attribution above are kept in this repository, and the
modifications are released under the same license.

## License

GLClash is released under the [GPL-3.0 license](LICENSE).