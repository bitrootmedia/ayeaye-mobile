import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../ui/theme.dart';

/// The frame every pre-sign-in screen sits in.
///
/// Deliberately plain: a person adding a self-hosted instance is doing
/// configuration, and configuration wants room and legible labels rather than
/// decoration.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.onBack,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.xl,
                vertical: Gap.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (onBack != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ShadButton.ghost(
                          onPressed: onBack,
                          leading: const Icon(LucideIcons.arrowLeft, size: 16),
                          child: const Text('Back'),
                        ),
                      ),
                    const SizedBox(height: Gap.lg),
                    const Wordmark(),
                    const SizedBox(height: Gap.xxl),
                    Text(title, style: context.texts.h3),
                    if (subtitle != null) ...[
                      const SizedBox(height: Gap.sm),
                      Text(subtitle!, style: context.texts.muted),
                    ],
                    const SizedBox(height: Gap.xl),
                    ...children,
                    if (footer != null) ...[
                      const SizedBox(height: Gap.xl),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// The app's name, set once so it looks the same everywhere it appears.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size * 1.7,
            height: size * 1.7,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.primary,
              borderRadius: BorderRadius.circular(size * 0.45),
            ),
            child: Icon(
              LucideIcons.anchor,
              size: size,
              color: context.colors.primaryForeground,
            ),
          ),
          SizedBox(width: size * 0.55),
          Text(
            'ayeaye',
            style: TextStyle(
              fontSize: size * 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: context.colors.foreground,
            ),
          ),
        ],
      );
}

/// A banner for the things that block a screen: a gate, a dead session, a
/// server that said no.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.message,
    this.icon = LucideIcons.circleAlert,
    this.destructive = false,
  });

  final String message;
  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? context.colors.destructive : context.colors.mutedForeground;
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: destructive
            ? context.colors.destructive.withValues(alpha: 0.08)
            : context.colors.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: destructive
              ? context.colors.destructive.withValues(alpha: 0.3)
              : context.colors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              message,
              style: context.texts.small.copyWith(color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
