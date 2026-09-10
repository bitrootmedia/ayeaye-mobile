import 'package:flutter/widgets.dart';

/// Status and priority are **ranked, never alphabetical**, and the rank is the
/// product's own order. Sorting these as strings puts `blocker` first and
/// `todo` last, which reads as nonsense on a board.
///
/// There is deliberately no `done` status: open/closed is a separate boolean
/// and a task can be closed at any status.
class TaskStatus {
  const TaskStatus(this.key, this.label, this.rank, this.color);

  final String key;
  final String label;
  final int rank;
  final Color color;

  static const todo = TaskStatus('todo', 'To do', 0, Color(0xFF64748B));
  static const inProgress = TaskStatus('in_progress', 'In progress', 1, Color(0xFF2563EB));
  static const review = TaskStatus('review', 'Review', 2, Color(0xFF7C3AED));
  static const onHold = TaskStatus('on_hold', 'On hold', 3, Color(0xFFD97706));
  static const blocker = TaskStatus('blocker', 'Blocker', 4, Color(0xFFDC2626));

  static const all = [todo, inProgress, review, onHold, blocker];

  /// Unknown keys degrade to a neutral chip rather than throwing: the server
  /// may grow a status before the app knows about it.
  static TaskStatus of(String key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return TaskStatus(key, _humanise(key), all.length, const Color(0xFF64748B));
  }
}

class TaskPriority {
  const TaskPriority(this.key, this.label, this.rank, this.color);

  final String key;
  final String label;
  final int rank;
  final Color color;

  static const critical = TaskPriority('critical', 'Critical', 0, Color(0xFFDC2626));
  static const urgent = TaskPriority('urgent', 'Urgent', 1, Color(0xFFEA580C));
  static const high = TaskPriority('high', 'High', 2, Color(0xFFD97706));
  static const normal = TaskPriority('normal', 'Normal', 3, Color(0xFF475569));
  static const low = TaskPriority('low', 'Low', 4, Color(0xFF94A3B8));
  static const veryLow = TaskPriority('very_low', 'Very low', 5, Color(0xFFCBD5E1));

  static const all = [critical, urgent, high, normal, low, veryLow];

  /// The default the server applies when none is sent.
  static const fallback = normal;

  static TaskPriority of(String key) {
    for (final p in all) {
      if (p.key == key) return p;
    }
    return TaskPriority(key, _humanise(key), all.length, const Color(0xFF475569));
  }

  /// Criticals and urgents are the ones worth a colour in a dense list.
  bool get isElevated => rank <= high.rank;
}

/// The planner's five fixed buckets, in the order the web app shows them.
class PlannerBucket {
  const PlannerBucket(this.key, this.label);

  final String key;
  final String label;

  static const today = PlannerBucket('today', 'Today');
  static const tomorrow = PlannerBucket('tomorrow', 'Tomorrow');
  static const thisWeek = PlannerBucket('this_week', 'This week');
  static const nextWeek = PlannerBucket('next_week', 'Next week');
  static const someday = PlannerBucket('someday', 'Someday');

  static const all = [today, tomorrow, thisWeek, nextWeek, someday];

  static PlannerBucket of(String key) {
    for (final b in all) {
      if (b.key == key) return b;
    }
    return PlannerBucket(key, _humanise(key));
  }
}

/// How a task list is ordered. The server does the sorting; an unknown key is
/// ignored rather than rejected, so shared links stay valid.
class TaskSort {
  const TaskSort(this.key, this.label, {this.defaultDescending = false});

  final String key;
  final String label;
  final bool defaultDescending;

  static const priority = TaskSort('priority', 'Priority');
  static const due = TaskSort('due_on', 'Due date');
  static const updated = TaskSort('updated_at', 'Recently updated', defaultDescending: true);
  static const created = TaskSort('created_at', 'Recently created', defaultDescending: true);
  static const title = TaskSort('title', 'Title');
  static const status = TaskSort('status', 'Status');

  static const all = [priority, due, updated, created, status, title];

  static TaskSort of(String key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return priority;
  }
}

String _humanise(String key) {
  if (key.isEmpty) return key;
  final words = key.split(RegExp('[_-]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return key;
  return words.first.substring(0, 1).toUpperCase() +
      words.first.substring(1) +
      (words.length > 1 ? ' ${words.sublist(1).join(' ')}' : '');
}

/// What the API will accept as an attachment.
///
/// `image/heic` is *not* on the list and it is the iPhone camera's default, so
/// pictures are converted to JPEG before they are declared.
const allowedUploadTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'application/pdf',
  'text/plain',
  'text/csv',
  'video/mp4',
  'video/webm',
  'audio/webm',
  'audio/mp4',
  'audio/mpeg',
};

/// `attachment_max_bytes` server-side default. Checked locally first: the real
/// size is enforced at *confirm*, so a too-large file otherwise fails after
/// the whole upload — a wasted trip on a phone connection.
const maxUploadBytes = 50 * 1024 * 1024;
