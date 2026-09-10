import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme.dart';

/// The top of every in-app screen.
///
/// A hand-rolled header rather than an `AppBar` so the org switcher, the title
/// and the actions share one consistent baseline, and so a screen can add a
/// filter bar underneath without the elevation and inset rules fighting it.
class ScreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const ScreenHeader({
    super.key,
    this.title,
    this.leading,
    this.actions = const [],
    this.bottom,
  });

  /// Either a plain title or a widget (the org switcher, usually).
  final Widget? title;

  final Widget? leading;
  final List<Widget> actions;

  /// A filter or search row, drawn below the title line.
  final Widget? bottom;

  /// Tall enough for the org switcher's two lines at a large text scale; the
  /// title row is Expanded, so it uses whatever this allows.
  static const _rowHeight = 58.0;

  @override
  Size get preferredSize => Size.fromHeight(_rowHeight + (bottom == null ? 0 : 44));

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.colors.background,
          border: Border(bottom: BorderSide(color: context.colors.border)),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Expanded, not a fixed height: Scaffold hands the app-bar slot
              // slightly less than `preferredSize` in some layouts, and a
              // fixed row overflows by a pixel when it does.
              Expanded(
                child: Row(
                  children: [
                    ?leading,
                    SizedBox(width: leading == null ? Gap.sm : 0),
                    Expanded(child: title ?? const SizedBox.shrink()),
                    ...actions,
                    const SizedBox(width: Gap.sm),
                  ],
                ),
              ),
              if (bottom != null) SizedBox(height: 44, child: bottom!),
            ],
          ),
        ),
      );
}

/// A plain screen title, for pushed routes.
class HeaderTitle extends StatelessWidget {
  const HeaderTitle(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: context.colors.foreground,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: context.colors.mutedForeground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
}

/// The back button used on every pushed route.
class HeaderBack extends StatelessWidget {
  const HeaderBack({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ShadIconButton.ghost(
        icon: const Icon(LucideIcons.chevronLeft, size: 20),
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      );
}

/// A section label used down the length of the longer screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ??
            const EdgeInsets.only(
              left: Gap.lg,
              right: Gap.lg,
              top: Gap.lg,
              bottom: Gap.sm,
            ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: context.colors.mutedForeground,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}
