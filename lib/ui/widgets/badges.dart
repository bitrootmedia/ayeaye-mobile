import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/models/enums.dart';
import '../../core/models/models.dart';
import '../format.dart';
import '../theme.dart';

/// A status chip: the status colour at low opacity behind solid text.
///
/// Statuses are a closed, ranked set, so they get a consistent shape rather
/// than being spelled out in prose.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = TaskStatus.of(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: context.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          fontSize: compact ? 10.5 : 11.5,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: context.isDark ? _lighten(s.color) : _darken(s.color),
        ),
      ),
    );
  }
}

/// Priority as a dot, not a word.
///
/// In a list of forty rows the priority of most of them is `normal`, and
/// forty labelled chips is noise; a dot that only gets loud for critical and
/// urgent keeps the eye where it belongs.
class PriorityDot extends StatelessWidget {
  const PriorityDot(this.priority, {super.key, this.size = 8});

  final String priority;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = TaskPriority.of(priority);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
    );
  }
}

class PriorityLabel extends StatelessWidget {
  const PriorityLabel(this.priority, {super.key});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final p = TaskPriority.of(priority);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PriorityDot(priority),
        const SizedBox(width: 6),
        Text(
          p.label,
          style: context.texts.small.copyWith(
            color: p.isElevated ? p.color : context.colors.mutedForeground,
            fontWeight: p.isElevated ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// The 3px rail down the left of a task row. The app's signature: it reads as
/// priority at a glance without occupying a column.
class PriorityRail extends StatelessWidget {
  const PriorityRail(this.priority, {super.key});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final p = TaskPriority.of(priority);
    return Container(
      width: 3,
      decoration: BoxDecoration(
        // Only elevated priorities earn a visible rail; the rest keep the row
        // quiet by fading into the border colour.
        color: p.isElevated ? p.color : context.colors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// A due date that colours itself by urgency.
class DueChip extends StatelessWidget {
  const DueChip(this.due, {super.key, this.icon = LucideIcons.calendar});

  final DateTime due;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final overdue = Fmt.isOverdue(due);
    final soon = Fmt.isSoon(due);
    final color = overdue
        ? context.colors.destructive
        : soon
            ? context.attention
            : context.colors.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        // Flexible: "Tomorrow" and "12 days ago" are different widths, and at
        // a large text scale the longer ones do not fit a dense row.
        Flexible(
          child: Text(
            Fmt.due(due),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: color,
              fontWeight: overdue || soon ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.tag, {super.key, this.onTap});

  final TagOut tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: context.colors.muted,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: context.colors.border),
          ),
          child: Text(
            tag.name,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.mutedForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
}

/// "You" or a colleague's name, marked as the person the task is waiting on.
///
/// `action_required` is the product's central idea, so it gets the attention
/// colour and nothing else does.
class ActionRequiredChip extends StatelessWidget {
  const ActionRequiredChip({
    super.key,
    required this.person,
    required this.isMe,
  });

  final PersonOut? person;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final label = person == null
        ? 'Unassigned'
        : isMe
            ? 'You'
            : Fmt.person(person!.displayName, person!.email);
    final unassigned = person == null;
    final color = unassigned
        ? context.colors.mutedForeground
        : isMe
            ? context.attention
            : context.colors.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          unassigned ? LucideIcons.userMinus : LucideIcons.userCheck,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: color,
            fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// A small counter, for tab badges and column headers.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.emphasised = false});

  final int count;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final bg = emphasised ? context.colors.destructive : context.colors.muted;
    final fg = emphasised
        ? context.colors.destructiveForeground
        : context.colors.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Initials in a circle, coloured deterministically from the person's id.
///
/// Deterministic so the same colleague is the same colour on every screen,
/// which is what makes an avatar scannable at all.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, this.person, this.size = 28, this.label});

  final PersonOut? person;
  final double size;

  /// Used when there is no [person] — e.g. a profile in the switcher.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = person != null
        ? Fmt.initials(person!.displayName, person!.email)
        : (label ?? '?');
    final seed = person?.id ?? label ?? '';
    final color = _avatarColor(seed, context.isDark);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

const _avatarPalette = [
  Color(0xFF0F766E),
  Color(0xFF1D4ED8),
  Color(0xFF7C3AED),
  Color(0xFFBE185D),
  Color(0xFFB45309),
  Color(0xFF047857),
  Color(0xFF4338CA),
  Color(0xFF9F1239),
];

Color _avatarColor(String seed, bool isDark) {
  if (seed.isEmpty) return const Color(0xFF64748B);
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  final base = _avatarPalette[hash % _avatarPalette.length];
  return isDark ? _lighten(base, 0.12) : base;
}

Color _darken(Color c, [double amount = 0.18]) =>
    Color.lerp(c, Colors.black, amount)!;

Color _lighten(Color c, [double amount = 0.35]) =>
    Color.lerp(c, Colors.white, amount)!;
