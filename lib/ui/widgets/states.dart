import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/api_exception.dart';
import '../theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: context.colors.primary,
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: Gap.md),
              Text(label!, style: context.texts.muted),
            ],
          ],
        ),
      );
}

/// The empty state for a list that legitimately has nothing in it.
///
/// Given its own widget because "no tasks yet" and "everything is triaged" are
/// good news, and a blank screen reads as a bug.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(Gap.lg),
                decoration: BoxDecoration(
                  color: context.colors.muted,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 26, color: context.colors.mutedForeground),
              ),
              const SizedBox(height: Gap.lg),
              Text(
                title,
                style: context.texts.large,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  message!,
                  style: context.texts.muted,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: Gap.lg),
                action!,
              ],
            ],
          ),
        ),
      );
}

/// Renders a failure the way the API means it.
///
/// The important case is 404: ayeaye reports "no access" as 404, never 403, so
/// a missing task and a task somebody revoked look identical on the wire — and
/// both should say "not found", not "forbidden".
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = _describe(error);
    return EmptyState(
      icon: icon,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : ShadButton.outline(
              onPressed: onRetry,
              leading: const Icon(LucideIcons.refreshCw, size: 15),
              child: const Text('Try again'),
            ),
    );
  }

  static (IconData, String, String) _describe(Object error) => switch (error) {
        NotFoundError() => (
            LucideIcons.searchX,
            'Not found',
            'This may have been deleted, or you may no longer have access to it.',
          ),
        ForbiddenError(:final message) => (
            LucideIcons.lock,
            'Not allowed',
            message,
          ),
        NetworkError(:final message) => (
            LucideIcons.wifiOff,
            'No connection',
            message,
          ),
        SessionExpiredError(:final message) => (
            LucideIcons.logOut,
            'Signed out',
            message,
          ),
        ApiException(:final message) => (
            LucideIcons.circleAlert,
            'Something went wrong',
            message,
          ),
        _ => (
            LucideIcons.circleAlert,
            'Something went wrong',
            error.toString(),
          ),
      };
}

/// Maps an [AsyncValue] onto the three states, keeping the previous data
/// visible while a refresh is in flight.
///
/// Showing a spinner over a list a person was already reading is the single
/// most common way a refresh feels broken, so a reload only dims.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    final current = value;
    if (current.hasValue) {
      final child = data(current.value as T);
      if (current.isLoading) {
        return Stack(
          children: [
            Opacity(opacity: 0.55, child: child),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopProgress(),
            ),
          ],
        );
      }
      return child;
    }
    if (current.hasError) {
      return ErrorView(error: current.error!, onRetry: onRetry);
    }
    return loading ?? const LoadingView();
  }
}

class _TopProgress extends StatelessWidget {
  const _TopProgress();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 2,
        child: LinearProgressIndicator(
          minHeight: 2,
          backgroundColor: Colors.transparent,
          color: context.colors.primary,
        ),
      );
}

/// A thin divider that matches the theme without being a full `ShadSeparator`
/// (which adds its own margins).
class HairLine extends StatelessWidget {
  const HairLine({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: EdgeInsets.only(left: indent),
        color: context.colors.border,
      );
}
