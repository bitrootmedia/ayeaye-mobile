import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Human-facing date and duration formatting.
///
/// Everything here leans relative ("in 3 days", "overdue by 2 days") because a
/// phone is where people ask *how urgent is this*, not *what is the date*.
class Fmt {
  static final _day = DateFormat('d MMM');
  static final _dayYear = DateFormat('d MMM yyyy');
  static final _weekday = DateFormat('EEE d MMM');
  static final _time = DateFormat('HH:mm');
  static final _dateTime = DateFormat('d MMM, HH:mm');
  static final _monthYear = DateFormat('MMMM yyyy');

  static String date(DateTime d) =>
      d.year == DateTime.now().year ? _day.format(d) : _dayYear.format(d);

  static String weekday(DateTime d) => _weekday.format(d);
  static String time(DateTime d) => _time.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);

  static String dateTime(DateTime d) =>
      d.year == DateTime.now().year ? _dateTime.format(d) : _dayYear.format(d);

  static String ago(DateTime d) => timeago.format(d, locale: 'en_short');

  static String agoLong(DateTime d) => timeago.format(d);

  /// A due date said the way a person would say it.
  static String due(DateTime date) {
    final days = _daysFromToday(date);
    return switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ when days < 0 => '${-days} days ago',
      _ when days <= 6 => _weekday.format(date),
      _ => date_(date),
    };
  }

  static String date_(DateTime d) => date(d);

  static bool isOverdue(DateTime date) => _daysFromToday(date) < 0;
  static bool isToday(DateTime date) => _daysFromToday(date) == 0;
  static bool isSoon(DateTime date) {
    final days = _daysFromToday(date);
    return days >= 0 && days <= 2;
  }

  /// Whole days between today and [date], ignoring clock time — "due
  /// tomorrow" should not flip at 00:01.
  static int _daysFromToday(DateTime date) {
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(date.year, date.month, date.day);
    return b.difference(a).inDays;
  }

  /// `2h 15m`, for time entries and the running timer.
  static String duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  /// `1:02:33`, for a timer that is ticking right now.
  static String stopwatch(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String seconds(int total) => duration(Duration(seconds: total));

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String count(int n, String singular, [String? plural]) =>
      n == 1 ? '$n $singular' : '$n ${plural ?? '${singular}s'}';

  /// Strips HTML to a one-line preview for list rows.
  ///
  /// Old descriptions are plain text and stay that way, so this has to cope
  /// with both shapes.
  static String preview(String? html, {int max = 120}) {
    if (html == null || html.isEmpty) return '';
    var text = html;
    if (text.contains('<')) {
      text = text
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'</(p|div|li|h2|h3)>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]*>'), '');
    }
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length <= max ? text : '${text.substring(0, max).trimRight()}…';
  }

  /// A person's name, falling back through the fields that might be set.
  static String person(String? displayName, String? email) {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail.split('@').first;
    return 'Someone';
  }

  static String initials(String? displayName, String? email) {
    final source = Fmt.person(displayName, email);
    final parts =
        source.split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
