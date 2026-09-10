import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Transient feedback.
///
/// Kept behind two functions so every screen says "saved" and "that failed"
/// the same way, and so the error path always shows the server's own `detail`
/// message — it is written to be read by a person.
void showToast(BuildContext context, String message, {String? title}) {
  ShadToaster.of(context).show(
    ShadToast(
      title: title == null ? null : Text(title),
      description: Text(message),
      duration: const Duration(seconds: 3),
    ),
  );
}

void showErrorToast(BuildContext context, Object error, {String? title}) {
  ShadToaster.of(context).show(
    ShadToast.destructive(
      title: Text(title ?? 'That did not work'),
      description: Text(error.toString()),
      duration: const Duration(seconds: 5),
    ),
  );
}

/// Runs [action], reporting failure as a toast, and returns whether it worked.
///
/// Almost every mutation in the app wants exactly this: optimistic UI, a toast
/// if the server disagreed, and no half-handled exceptions.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
  String? errorTitle,
}) async {
  try {
    await action();
    if (context.mounted && success != null) showToast(context, success);
    return true;
  } catch (error) {
    if (context.mounted) showErrorToast(context, error, title: errorTitle);
    return false;
  }
}
