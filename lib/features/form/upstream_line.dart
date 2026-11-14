/// What a pasted line says, or the field it could not fill.
///
/// Providers hand out one line in one of a few shapes, so the short form reads
/// the common ones instead of making the user split them by hand:
///
/// - `host:port:user:pass`, the order most of them use
/// - `host:port` alone, for a hop with no account
/// - `user:pass@host:port`
/// - a URL, `socks5://user:pass@host:port` / `http://host:port`
typedef ParsedUpstreamLine = ({
  String? type,
  String server,
  int port,
  String username,
  String password,
});

/// Reads [line] into the fields of the short form, or null when it is not a
/// shape this understands.
///
/// A password may hold colons, so everything past the third one belongs to it;
/// that is why the split is bounded rather than a plain `split(':')`.
ParsedUpstreamLine? parseUpstreamLine(String line) {
  var text = line.trim();
  if (text.isEmpty) {
    return null;
  }
  String? type;
  var isUrl = false;
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(text);
  if (scheme != null) {
    final name = scheme.group(1)!.toLowerCase();
    // Only the two kinds the form offers; any other scheme is left to the
    // session it belongs to.
    if (name != 'socks5' && name != 'socks5h' && name != 'http') {
      return null;
    }
    type = name == 'http' ? 'http' : 'socks5';
    text = text.substring(scheme.end);
    isUrl = true;
  }
  // Only a URL has a path, query or fragment after its address. In the other
  // shapes every character belongs to a field, so a password holding '/', '?'
  // or '#' keeps it.
  if (isUrl) {
    final cut = text.indexOf(RegExp(r'[/?#]'));
    if (cut >= 0) {
      text = text.substring(0, cut);
    }
  }
  if (text.isEmpty) {
    return null;
  }

  // The host comes first in every shape, so its own port decides where the
  // address ends; whatever follows is the account, where '@' is just another
  // character a password may hold.
  final head = _headOf(text);
  if (head != null) {
    final rest = text.substring(head.end);
    if (rest.isEmpty) {
      return (
        type: type,
        server: head.server,
        port: head.port,
        username: '',
        password: '',
      );
    }
    final account = rest.startsWith(':') ? rest.substring(1) : rest;
    final colon = account.indexOf(':');
    return (
      type: type,
      server: head.server,
      port: head.port,
      username: _decode(
        colon < 0 ? account.trim() : account.substring(0, colon).trim(),
      ),
      password: _decode(colon < 0 ? '' : account.substring(colon + 1)),
    );
  }

  // `user:pass@host:port` puts the account first, which the head could not
  // read; the last '@' is the separator because a password may hold more.
  final at = text.lastIndexOf('@');
  if (at <= 0) {
    return null;
  }
  final credentials = text.substring(0, at);
  final address = _hostPort(text.substring(at + 1));
  if (address == null) {
    return null;
  }
  final colon = credentials.indexOf(':');
  return (
    type: type,
    server: address.server,
    port: address.port,
    username: _decode(
      colon < 0 ? credentials : credentials.substring(0, colon),
    ),
    password: _decode(colon < 0 ? '' : credentials.substring(colon + 1)),
  );
}

/// The `host:port` at the start of [text], with where it ends.
({String server, int port, int end})? _headOf(String text) {
  final bracketed = RegExp(r'^(\[[^\]]+\]):(\d+)').firstMatch(text);
  if (bracketed != null) {
    final address = _hostPort(bracketed.group(0)!);
    if (address == null) {
      return null;
    }
    return (server: address.server, port: address.port, end: bracketed.end);
  }
  // A plain host holds no colon, so the first one ends the address; a later
  // colon belongs to the account that follows.
  final plain = RegExp(r'^(!?[^:\s]+):(\d+)').firstMatch(text);
  if (plain == null) {
    return null;
  }
  final port = int.tryParse(plain.group(2)!);
  if (port == null || port < 1 || port > 65535) {
    return null;
  }
  // `host:port:user:pass` is the shape here; `user:pass@host:port` fails the
  // port check on its first colon and reaches the '@' branch instead.
  return (server: plain.group(1)!, port: port, end: plain.end);
}

({String server, int port})? _hostPort(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  // `[::1]:1080` keeps its brackets off the server but its port on.
  final bracketed = RegExp(r'^\[([^\]]+)\]:(\d+)$').firstMatch(trimmed);
  final match = bracketed ?? RegExp(r'^(.+):(\d+)$').firstMatch(trimmed);
  if (match == null) {
    return null;
  }
  final port = int.tryParse(match.group(2)!);
  final server = match.group(1)!.trim();
  if (port == null || port < 1 || port > 65535 || server.isEmpty) {
    return null;
  }
  return (server: server, port: port);
}

/// Percent-decoding, so a credential a provider encoded still arrives whole.
///
/// A provider that encoded in another charset, or a stray `%` in a generated
/// password, makes the decoder throw; the raw text is then what it meant.
String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  } on ArgumentError {
    return value;
  }
}
