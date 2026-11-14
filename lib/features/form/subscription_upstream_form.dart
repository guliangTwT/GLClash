import 'package:gl_clash/common/common.dart';
import 'package:gl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'form_page.dart';
import 'form_row.dart';

/// Picks a subscription's node to dial through: an empty filter takes the whole
/// subscription, which the group lists as its members.
Future<String?> showSubscriptionUpstreamForm(
  BuildContext context, {
  required String title,
}) {
  return showFormSheet<String>(
    context: context,
    builder: (_) => SubscriptionUpstreamForm(title: title),
  );
}

class SubscriptionUpstreamForm extends StatefulWidget {
  final String title;

  const SubscriptionUpstreamForm({super.key, required this.title});

  @override
  State<SubscriptionUpstreamForm> createState() =>
      _SubscriptionUpstreamFormState();
}

class _SubscriptionUpstreamFormState extends State<SubscriptionUpstreamForm> {
  final _filter = TextEditingController();
  final _filterFocus = FocusNode();

  @override
  void dispose() {
    _filter.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return FormPage(
      title: widget.title,
      onSave: () => Navigator.of(context).pop(_filter.text.trim()),
      children: [
        generateSection(
          items: [
            FormRow(
              title: l.chainSubscriptionFilter,
              trailing: FormRowTextField(
                controller: _filter,
                focusNode: _filterFocus,
                autofocus: true,
                hintText: l.optional,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                inputFormatters: TextInputLimits.limit(TextInputLimits.filter),
                onFieldSubmitted: (_) =>
                    Navigator.of(context).pop(_filter.text.trim()),
              ),
            ),
            FormRow(
              title: '',
              trailing: Text(
                l.chainSubscriptionFilterDesc,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
