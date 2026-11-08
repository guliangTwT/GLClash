import 'package:gl_clash/common/context.dart';
import 'package:gl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Shows the download of a release asset. [onCancel] stops the transfer and
/// the caller closes the dialog once the incomplete file is gone, so a cancelled
/// download never sits around looking installable.
class UpdateProgressDialog extends StatelessWidget {
  final ValueNotifier<double?> progress;
  final VoidCallback onCancel;

  const UpdateProgressDialog({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.downloadingUpdate,
      actions: [
        TextButton(onPressed: onCancel, child: Text(appLocalizations.cancel)),
      ],
      child: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (context, value, _) {
          final percentage = value == null ? null : (value * 100).round();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              LinearProgressIndicator(
                minHeight: 4,
                value: value,
                backgroundColor: context.colorScheme.primary.opacity15,
              ),
              Text(
                percentage == null
                    ? appLocalizations.downloadingUpdate
                    : '$percentage%',
                textAlign: TextAlign.center,
                style: AppTextStyle.subheadline.of(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
