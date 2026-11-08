import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
  });
}

// rquickjs runs bindgen on Android, which must load a libclang. Linux NDKs
// before r26 keep it under lib64, later ones and every macOS NDK under lib.
// The Windows NDK ships none, so LIBCLANG_PATH from the environment wins when
// it points at one, and the NDK's builtin headers have to be added by hand: a
// libclang picked up that way does not know where they are.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return const {};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  final configured = Platform.environment['LIBCLANG_PATH'];
  final installed = _libclangDirectory(Directory(configured ?? ''));
  if (installed != null) {
    return {
      'LIBCLANG_PATH': installed,
      ..._ndkClangArguments(input, llvmRoot.path),
    };
  }
  for (final name in const ['lib', 'lib64']) {
    final found = _libclangDirectory(
      Directory('${llvmRoot.path}${Platform.pathSeparator}$name'),
    );
    if (found != null) {
      return {'LIBCLANG_PATH': found};
    }
  }
  throw StateError(
    'No libclang under ${llvmRoot.path} (lib or lib64); the NDK Flutter '
    'passed cannot run bindgen for rquickjs. Point LIBCLANG_PATH at a '
    'directory holding one if the NDK ships without it.',
  );
}

/// What native_toolchain_rust would pass for [input], plus the NDK's builtin
/// includes, which only the NDK's own libclang locates on its own.
Map<String, String> _ndkClangArguments(BuildInput input, String llvmRoot) {
  final rustTriple = const {
    'arm': 'armv7-linux-androideabi',
    'arm64': 'aarch64-linux-android',
    'ia32': 'i686-linux-android',
    'x64': 'x86_64-linux-android',
  }[input.config.code.targetArchitecture.name];
  if (rustTriple == null) {
    return const {};
  }
  final includeTriple = rustTriple == 'armv7-linux-androideabi'
      ? 'arm-linux-androideabi'
      : rustTriple;
  final builtin = _builtinIncludes(llvmRoot);
  final arguments = [
    '--sysroot=$llvmRoot/sysroot',
    '-I$llvmRoot/sysroot/usr/include/$includeTriple',
    if (builtin != null) '-isystem $builtin',
  ].join(' ').replaceAll(r'\', '/');
  return {
    'BINDGEN_EXTRA_CLANG_ARGS_${rustTriple.replaceAll('-', '_')}': arguments,
  };
}

String? _builtinIncludes(String llvmRoot) {
  final versions = Directory('$llvmRoot/lib/clang');
  if (!versions.existsSync()) {
    return null;
  }
  for (final version in versions.listSync().whereType<Directory>()) {
    final include = Directory(
      '${version.path}${Platform.pathSeparator}include',
    );
    if (include.existsSync()) {
      return include.path;
    }
  }
  return null;
}

String? _libclangDirectory(Directory root) {
  if (!root.existsSync()) {
    return null;
  }
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && _isLibclang(entity)) {
      return entity.parent.path;
    }
  }
  return null;
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}
