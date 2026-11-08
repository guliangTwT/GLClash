<div align="center">

<img src="assets/images/icon.png" alt="GLClash" width="88">

# GLClash

基于 mihomo（Clash.Meta）的多平台代理客户端，界面清爽，开源无广告。

[English](README.md) · **简体中文**

[![Release](https://img.shields.io/github/v/release/guliangTwT/GLClash?style=flat-square&label=release)](https://github.com/guliangTwT/GLClash/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/guliangTwT/GLClash/total?style=flat-square&logo=github)](https://github.com/guliangTwT/GLClash/releases)
[![License](https://img.shields.io/github/license/guliangTwT/GLClash?style=flat-square)](LICENSE)

[下载](#下载) · [更新日志](CHANGELOG.md) · [从源码构建](#从源码构建) · [来源与致谢](#来源与致谢)

</div>

## 关于 GLClash

GLClash 是基于 [FlClash](https://github.com/chen08209/FlClash) 源码重新命名的发行版：应用名、图标名、
Android 包名（`com.glclash.app`）、Windows/Linux 可执行文件名、内核与 Helper 服务名（`GLClashCore`、
`GLClashHelperService`）、URL Scheme（`glclash://`）以及全部界面文案都已统一为 GLClash，同时修正了若干
更新检查与打包相关的问题，详见 [CHANGELOG.md](CHANGELOG.md)。

内核仍是 mihomo（Clash.Meta），协议与配置格式和 Clash 生态完全兼容。GLClash 与 FlClash 使用**不同的数据目录**，
两者可以并存安装，配置互不影响：

| 平台 | GLClash 数据目录 |
| --- | --- |
| Windows | `%APPDATA%\GuLiang-I\GLClash` |
| Android | 应用私有目录 `com.glclash.app` |
| macOS / Linux | 按包名 `com.glclash.app` 区分 |

## 功能

- **Android、Windows、macOS、Linux 同一套代码**，桌面端提供 x64 与 ARM64 构建。
- **mihomo 内核**：规则分流、代理组、延迟测试、系统代理与 TUN 模式。
- **配置管理**：订阅链接或文件导入，内置编辑器，支持覆写脚本与自定义规则、代理、代理组。
- **实时查看**连接、请求、DNS 查询与日志。
- **Material You 设计融合 Apple 式交互**：动态取色、浅深色主题、连续曲率圆角、可吸附的弹出面板、
  从手机到桌面的自适应布局。
- **备份与恢复**：WebDAV 或本地文件。
- **平台细节**：Android 快捷设置磁贴、分应用代理、Android TV；桌面托盘菜单与全局快捷键。
- **开源无广告**，以 GPL-3.0 协议发布。

## 下载

只从 [GitHub Releases](https://github.com/guliangTwT/GLClash/releases/latest) 下载，每个版本同时发布在
[Codeberg 镜像](https://codeberg.org/GuLiang/GLClash/releases/latest)。当前版本发布的安装包：

| 平台 | 安装包 | 说明 |
| --- | --- | --- |
| Android | `GLClash-<版本>-android-arm64-v8a.apk` | 绝大多数手机选它；另有 `armeabi-v7a`、`x86_64`。 |
| Windows 10 及以上 | `GLClash-<版本>-windows-amd64-setup.exe` | 安装版（Inno Setup），也可用同页的 `.zip` 便携版。 |

ARM64 桌面版、macOS 的 DMG 与 Linux 的 deb/rpm/AppImage 需要对应系统的编译环境，本仓库的发布流程暂未提供，
可参照[从源码构建](#从源码构建)自行打包。

## 使用

**通过链接导入配置。** 打开下面格式的链接即可把订阅导入 GLClash；`clashmeta://` 与 `glclash://` 开头的链接同样可用。

```text
clash://install-config?url=<经过 URL 编码的订阅链接>
```

**Android 自动化。** Tasker、MacroDroid 等应用可以用下面的 Action 启动 Activity，启动、停止或切换代理：

```text
com.glclash.app.action.START
com.glclash.app.action.STOP
com.glclash.app.action.TOGGLE
```

电脑上也可以用 adb 触发：

```bash
adb shell am start -a com.glclash.app.action.TOGGLE
```

**无人值守的桌面环境。** GLClash 在免责声明被接受后才会启动内核。容器等无人点击的环境里，可设置环境变量
`GLCLASH_ACCEPT_DISCLAIMER=1`，首次启动即视为接受。

## 从源码构建

需要 [Flutter](https://docs.flutter.dev/get-started/install) 3.47（正式版构建使用 3.47.6）、[Go](https://go.dev/dl/) 1.27，
以及通过 rustup 安装的 [Rust](https://rustup.rs/)。

```bash
git clone --recursive https://github.com/guliangTwT/GLClash.git
cd GLClash
flutter pub get
dart setup.dart windows   # 或 android、macos、linux
```

安装包输出到 `dist/`；Go 内核与 Rust 库由 Flutter 的构建钩子一并编译，产物落在 `libclash/`。

| 平台 | 额外依赖 |
| --- | --- |
| Android | 带 NDK 的 Android SDK 与 JDK 17+。加 `--arch arm64` 可只构建单个 ABI。 |
| Windows | Visual Studio 2022 的「使用 C++ 的桌面开发」，以及打包安装程序用的 [Inno Setup](https://jrsoftware.org/isinfo.php) 6。 |
| macOS | Xcode 与 Node.js（脚本会通过 npm 安装 `appdmg`）。 |
| Linux | Debian 或 Ubuntu；脚本会用 apt 安装所需软件包并下载 `appimagetool`。 |

其余选项见 `dart setup.dart --help`，例如用 `--targets` 只打包部分格式。

> 源码体积较大且 `core/Clash.Meta` 是子模块，克隆时务必带 `--recursive`；已克隆的可执行
> `git submodule update --init --recursive`。

## 来源与致谢

- [FlClash](https://github.com/chen08209/FlClash)：本项目的界面、架构与构建流程来源，感谢原作者 chen08209。
- [mihomo / Clash.Meta](https://github.com/MetaCubeX/mihomo)：代理内核。
- 以及 FlClash 依赖的所有开源项目与翻译贡献者。

按 GPL-3.0 的要求，本仓库保留了原始 [LICENSE](LICENSE) 全文与上述来源说明；修改内容同样以 GPL-3.0 发布。

## 许可证

GLClash 以 [GPL-3.0 协议](LICENSE)发布。