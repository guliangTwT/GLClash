import 'package:gl_clash/common/common.dart';
import 'package:gl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'form_page.dart';
import 'form_row.dart';

/// A proxy typed in by hand: the type, where it is, and the account it takes.
///
/// This is the whole of what a SOCKS5 or HTTP hop needs, and the only two
/// kinds offered, so creating an upstream never depends on knowing the other
/// protocol's options first.
typedef UpstreamProxy = ({
  String type,
  String server,
  int port,
  String username,
  String password,
});

/// The types the short form offers, in the order it lists them.
const upstreamProxyTypes = ['socks5', 'http'];

Future<UpstreamProxy?> showUpstreamProxyForm(
  BuildContext context, {
  required String title,
  UpstreamProxy? initial,
}) {
  return showFormSheet<UpstreamProxy>(
    context: context,
    builder: (_) => UpstreamProxyForm(title: title, initial: initial),
  );
}

enum _Field { type, server, port, username, password }

class UpstreamProxyForm extends StatefulWidget {
  final String title;
  final UpstreamProxy? initial;

  const UpstreamProxyForm({super.key, required this.title, this.initial});

  @override
  State<UpstreamProxyForm> createState() => _UpstreamProxyFormState();
}

class _UpstreamProxyFormState extends State<UpstreamProxyForm> {
  final _serverFocus = FocusNode();
  final _portFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  late final TextEditingController _server;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late String _type;
  var _attempted = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type = initial?.type ?? upstreamProxyTypes.first;
    _server = TextEditingController(text: initial?.server ?? '');
    _port = TextEditingController(
      text: initial == null ? '' : '${initial.port}',
    );
    _username = TextEditingController(text: initial?.username ?? '');
    _password = TextEditingController(text: initial?.password ?? '');
  }

  @override
  void dispose() {
    _serverFocus.dispose();
    _portFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _server.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  ({_Field field, String message})? _issue() {
    final l = context.appLocalizations;
    if (_server.text.trim().isEmpty) {
      return (field: _Field.server, message: l.emptyTip(l.server));
    }
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      return (field: _Field.port, message: l.chainUpstreamPortInvalid);
    }
    return null;
  }

  void _handleSubmit() {
    final issue = _issue();
    if (issue != null) {
      setState(() {
        _attempted = true;
      });
      return;
    }
    Navigator.of(context).pop<UpstreamProxy>((
      type: _type,
      server: _server.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      password: _password.text,
    ));
  }

  void _handleChanged(String _) {
    if (_attempted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final issue = _attempted ? _issue() : null;
    return FormPage(
      title: widget.title,
      onSave: _handleSubmit,
      error: issue?.message,
      children: [
        generateSection(
          items: [
            ListItem<String>.options(
              title: Text(l.upstreamType),
              options: upstreamProxyTypes,
              value: _type,
              textBuilder: (type) => type.toUpperCase(),
              onChanged: (value) => setState(() {
                _type = value;
              }),
            ),
            FormRow(
              title: l.server,
              invalid: issue?.field == _Field.server,
              trailing: FormRowTextField(
                controller: _server,
                autofocus: true,
                hintText: '127.0.0.1',
                textInputAction: TextInputAction.next,
                autocorrect: false,
                onChanged: _handleChanged,
                onFieldSubmitted: (_) => _portFocus.requestFocus(),
              ),
            ),
            FormRow(
              title: l.port,
              invalid: issue?.field == _Field.port,
              trailing: FormRowTextField(
                controller: _port,
                focusNode: _portFocus,
                hintText: '1080',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: TextInputLimits.digitsOnly(
                  TextInputLimits.port,
                ),
                onChanged: _handleChanged,
                onFieldSubmitted: (_) => _usernameFocus.requestFocus(),
              ),
            ),
            FormRow(
              title: l.username,
              trailing: FormRowTextField(
                controller: _username,
                focusNode: _usernameFocus,
                hintText: l.optional,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                inputFormatters: TextInputLimits.limit(
                  TextInputLimits.userName,
                ),
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
            ),
            FormRow(
              title: l.password,
              trailing: FormRowSecretTextField(
                controller: _password,
                focusNode: _passwordFocus,
                hintText: l.optional,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleSubmit(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
