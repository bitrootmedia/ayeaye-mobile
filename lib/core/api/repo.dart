import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../models/models.dart';
import 'api_client.dart';

/// The whole typed API surface, in one place.
///
/// Thin on purpose: every method is a path plus a decode. Filtering, sorting
/// and access are all the server's job, so there is no business logic to hide
/// here — and keeping it flat means a screen can be read against the endpoint
/// map without chasing layers.
class Repo {
  const Repo(this.api);

  final ApiClient api;

  String _org(String orgId) => '/api/organisations/$orgId';

  // ================================================================== me

  Future<MeOut> me() async => MeOut.fromJson(await api.getObject('/api/me'));

  Future<MeOut> updateMe(MeUpdate update) async =>
      MeOut.fromJson(await _obj(api.patch('/api/me', body: update.toJson())));

  Future<void> changePassword(String current, String next) => api.post(
        '/api/me/password',
        body: {'current_password': current, 'new_password': next},
      );

  Future<List<OrganisationOut>> organisations() =>
      api.getList('/api/organisations', OrganisationOut.fromJson);

  Future<OrganisationOut> createOrganisation(String name) async =>
      OrganisationOut.fromJson(
        await _obj(api.post('/api/organisations', body: {'name': name})),
      );

  Future<List<PendingInviteOut>> myInvites() =>
      api.getList('/api/me/invites', PendingInviteOut.fromJson);

  Future<void> acceptInvite(String memberId) =>
      api.post('/api/me/invites/$memberId/accept');

  Future<void> declineInvite(String memberId) =>
      api.delete('/api/me/invites/$memberId');

  // ---------------------------------------------------------- two-factor

  Future<MfaStatusOut> mfaStatus() async =>
      MfaStatusOut.fromJson(await api.getObject('/api/me/mfa/status'));

  /// Starts enrolment. The secret is not stored until it is confirmed, so it
  /// must be handed back to [verifyTotp] along with the code.
  Future<TotpDeviceOut> startTotpEnrolment() async =>
      TotpDeviceOut.fromJson(await _obj(api.post('/api/me/mfa/totp')));

  Future<BackupCodesOut> verifyTotp({
    required String secret,
    required String code,
  }) async =>
      BackupCodesOut.fromJson(await _obj(api.post(
        '/api/me/mfa/totp/verify',
        body: {'secret': secret, 'code': code},
      )));

  Future<void> disableTotp() => api.delete('/api/me/mfa/totp');

  Future<BackupCodesOut> regenerateBackupCodes() async =>
      BackupCodesOut.fromJson(await _obj(api.post('/api/me/mfa/backup-codes')));

  // ------------------------------------------------------------- tokens

  Future<List<TokenOut>> tokens() =>
      api.getList('/api/me/tokens', TokenOut.fromJson);

  Future<void> revokeToken(String id) => api.delete('/api/me/tokens/$id');

  // ------------------------------------------------------------ channels

  Future<List<NotificationChannelOut>> notificationChannels() => api.getList(
        '/api/me/notification-channels',
        NotificationChannelOut.fromJson,
      );

  Future<void> updateChannel(String id, List<String> enabledKinds) => api.patch(
        '/api/me/notification-channels/$id',
        body: {'enabled_kinds': enabledKinds},
      );

  Future<void> deleteChannel(String id) =>
      api.delete('/api/me/notification-channels/$id');

  // ======================================================= notifications

  Future<List<NotificationOut>> notifications({
    bool unreadOnly = false,
    int limit = 50,
  }) =>
      api.getList(
        '/api/notifications',
        NotificationOut.fromJson,
        query: {'unread_only': unreadOnly, 'limit': limit},
      );

  /// The inbox badge. There are no push notifications on the server today, so
  /// the app polls this the way the web app does.
  Future<int> unreadCount() async =>
      UnreadCountOut.fromJson(await api.getObject('/api/notifications/unread-count'))
          .unread;

  Future<void> markRead(String id) =>
      api.post('/api/notifications/$id/read');

  Future<void> markAllRead() => api.post('/api/notifications/read-all');

  Future<void> deleteNotification(String id) =>
      api.delete('/api/notifications/$id');

  // ============================================================ reminders

  Future<List<ReminderOut>> reminders() =>
      api.getList('/api/reminders', ReminderOut.fromJson);

  Future<int> remindersDueCount() async {
    final raw = await api.getObject('/api/reminders/due-count');
    return asIntish(raw['due']) ?? asIntish(raw['count']) ?? 0;
  }

  Future<ReminderOut> updateReminder(String id, ReminderUpdate update) async =>
      ReminderOut.fromJson(
        await _obj(api.patch('/api/reminders/$id', body: update.toJson())),
      );

  Future<void> deleteReminder(String id) => api.delete('/api/reminders/$id');

  /// A reminder with no task behind it, scoped to an organisation.
  Future<ReminderOut> createStandaloneReminder(
    String orgId,
    StandaloneReminderIn body,
  ) async =>
      ReminderOut.fromJson(
        await _obj(api.post('${_org(orgId)}/reminders', body: body.toJson())),
      );

  // =============================================================== sparks

  /// Quick capture — ⌘J on the web, and one of the two things people open the
  /// app for daily.
  Future<List<SparkOut>> sparks() =>
      api.getList('/api/sparks', SparkOut.fromJson);

  Future<SparkOut> createSpark(String body) async => SparkOut.fromJson(
        await _obj(api.post('/api/sparks', body: {'body': body})),
      );

  Future<SparkOut> updateSpark(String id, String body) async =>
      SparkOut.fromJson(
        await _obj(api.patch('/api/sparks/$id', body: {'body': body})),
      );

  Future<void> deleteSpark(String id) => api.delete('/api/sparks/$id');

  // ================================================================ timer

  /// The running timer, across every organisation. The other thing people open
  /// the app for daily.
  Future<TimerOut> myTimer() async =>
      TimerOut.fromJson(await api.getObject('/api/me/timer'));

  Future<void> stopTimer() => api.post('/api/me/timer/stop');

  Future<StartTimerOut> startTimer(String orgId, String taskId) async =>
      StartTimerOut.fromJson(
        await _obj(api.post('${_org(orgId)}/tasks/$taskId/time/start')),
      );

  Future<List<TimeEntryOut>> taskTime(String orgId, String taskId) => api.getList(
        '${_org(orgId)}/tasks/$taskId/time',
        TimeEntryOut.fromJson,
      );

  Future<TimeEntryOut> logTime(
    String orgId,
    String taskId,
    ManualEntryIn entry,
  ) async =>
      TimeEntryOut.fromJson(await _obj(
        api.post('${_org(orgId)}/tasks/$taskId/time', body: entry.toJson()),
      ));

  Future<List<TimeEntryOut>> timeEntries(
    String orgId, {
    String? userId,
    DateTime? start,
    DateTime? end,
  }) =>
      api.getList(
        '${_org(orgId)}/time/entries',
        TimeEntryOut.fromJson,
        query: {
          'user_id': userId,
          'start': fmtDay(start),
          'end': fmtDay(end),
        },
      );

  Future<void> deleteTimeEntry(String orgId, String entryId) =>
      api.delete('${_org(orgId)}/time/$entryId');

  Future<TimeSummaryOut> timeSummary(
    String orgId, {
    DateTime? start,
    DateTime? end,
  }) async =>
      TimeSummaryOut.fromJson(await api.getObject(
        '${_org(orgId)}/time/summary',
        query: {'start': fmtDay(start), 'end': fmtDay(end)},
      ));

  // ================================================================ tasks

  /// The task list. Paged with `limit`/`offset` and a real `X-Total-Count`;
  /// there is **no default limit**, so one is always sent.
  Future<Paged<TaskOut>> tasks(
    String orgId, {
    String? projectId,
    String? status,
    String? priority,
    String? tagId,
    String? ownerUserId,
    String? actionRequiredUserId,
    bool actionRequiredUnset = false,
    bool includeClosed = false,
    bool includeOffBoard = false,
    bool loose = false,
    String? sort,
    String dir = 'asc',
    int limit = 50,
    int offset = 0,
  }) =>
      api.getPaged(
        '${_org(orgId)}/tasks',
        TaskOut.fromJson,
        query: {
          'project_id': projectId,
          'status': status,
          'priority': priority,
          'tag_id': tagId,
          'owner_user_id': ownerUserId,
          'action_required_user_id': actionRequiredUserId,
          if (actionRequiredUnset) 'action_required_unset': true,
          if (includeClosed) 'include_closed': true,
          if (includeOffBoard) 'include_off_board': true,
          if (loose) 'loose': true,
          'sort': sort,
          'dir': dir,
          'limit': limit,
          'offset': offset,
        },
      );

  Future<TaskOut> task(String orgId, String taskId) async =>
      TaskOut.fromJson(await api.getObject('${_org(orgId)}/tasks/$taskId'));

  Future<TaskOut> createTask(String orgId, TaskCreate body) async =>
      TaskOut.fromJson(
        await _obj(api.post('${_org(orgId)}/tasks', body: body.toJson())),
      );

  Future<TaskOut> updateTask(
    String orgId,
    String taskId,
    Map<String, dynamic> patch,
  ) async =>
      TaskOut.fromJson(
        await _obj(api.patch('${_org(orgId)}/tasks/$taskId', body: patch)),
      );

  Future<void> deleteTask(String orgId, String taskId) =>
      api.delete('${_org(orgId)}/tasks/$taskId');

  Future<void> setClosed(String orgId, String taskId, bool closed) =>
      api.post('${_org(orgId)}/tasks/$taskId/closed', body: {'closed': closed});

  Future<void> setHidden(String orgId, String taskId, bool hidden) =>
      api.post('${_org(orgId)}/tasks/$taskId/hidden', body: {'hidden': hidden});

  Future<void> setPinned(String orgId, String taskId, bool pinned) => pinned
      ? api.post('${_org(orgId)}/tasks/$taskId/pin')
      : api.delete('${_org(orgId)}/tasks/$taskId/pin');

  /// The board has its own endpoint and **cannot be paged**: rows come back
  /// priority-first, so taking the first N of a large set would fill every
  /// column with criticals and leave the rest empty. It bounds each column
  /// server-side and reports each column's real size.
  Future<BoardOut> board(
    String orgId, {
    String group = 'status',
    int perGroup = 50,
    String? projectId,
    String? tagId,
    bool includeClosed = false,
    bool loose = false,
  }) async =>
      BoardOut.fromJson(await api.getObject(
        '${_org(orgId)}/tasks/board',
        query: {
          'group': group,
          'per_group': perGroup,
          'project_id': projectId,
          'tag_id': tagId,
          if (includeClosed) 'include_closed': true,
          if (loose) 'loose': true,
        },
      ));

  Future<List<TaskOut>> similarTasks(String orgId, String title) => api.getList(
        '${_org(orgId)}/tasks/similar',
        TaskOut.fromJson,
        query: {'title': title},
      );

  Future<List<TaskEventOut>> taskEvents(String orgId, String taskId) =>
      api.getList('${_org(orgId)}/tasks/$taskId/events', TaskEventOut.fromJson);

  Future<List<TaskRevisionOut>> taskRevisions(String orgId, String taskId) =>
      api.getList(
        '${_org(orgId)}/tasks/$taskId/revisions',
        TaskRevisionOut.fromJson,
      );

  Future<void> restoreRevision(String orgId, String taskId, String revisionId) =>
      api.post('${_org(orgId)}/tasks/$taskId/revisions/$revisionId/restore');

  Future<NoteOut> taskNote(String orgId, String taskId) async =>
      NoteOut.fromJson(await api.getObject('${_org(orgId)}/tasks/$taskId/note'));

  Future<NoteOut> saveTaskNote(String orgId, String taskId, String body) async =>
      NoteOut.fromJson(
        await _obj(api.put('${_org(orgId)}/tasks/$taskId/note', body: {'body': body})),
      );

  // ------------------------------------------------------------ checklists

  Future<List<ChecklistOut>> checklists(String orgId, String taskId) =>
      api.getList('${_org(orgId)}/tasks/$taskId/checklists', ChecklistOut.fromJson);

  Future<ChecklistOut> addChecklist(String orgId, String taskId, String title) async =>
      ChecklistOut.fromJson(await _obj(api.post(
        '${_org(orgId)}/tasks/$taskId/checklists',
        body: {'title': title},
      )));

  Future<void> deleteChecklist(String orgId, String taskId, String id) =>
      api.delete('${_org(orgId)}/tasks/$taskId/checklists/$id');

  Future<ChecklistItemOut> addChecklistItem(
    String orgId,
    String taskId,
    String checklistId,
    String text,
  ) async =>
      ChecklistItemOut.fromJson(await _obj(api.post(
        '${_org(orgId)}/tasks/$taskId/checklists/$checklistId/items',
        body: {'text': text},
      )));

  Future<ChecklistItemOut> setChecklistItemDone(
    String orgId,
    String taskId,
    String checklistId,
    String itemId,
    bool done,
  ) async =>
      ChecklistItemOut.fromJson(await _obj(api.patch(
        '${_org(orgId)}/tasks/$taskId/checklists/$checklistId/items/$itemId',
        body: {'done': done},
      )));

  Future<void> deleteChecklistItem(
    String orgId,
    String taskId,
    String checklistId,
    String itemId,
  ) =>
      api.delete(
        '${_org(orgId)}/tasks/$taskId/checklists/$checklistId/items/$itemId',
      );

  // ---------------------------------------------------------- dependencies

  Future<TaskDependenciesOut> dependencies(String orgId, String taskId) async =>
      TaskDependenciesOut.fromJson(
        await api.getObject('${_org(orgId)}/tasks/$taskId/dependencies'),
      );

  Future<void> addDependency(String orgId, String taskId, String dependsOn) =>
      api.post(
        '${_org(orgId)}/tasks/$taskId/dependencies',
        body: {'depends_on_task_id': dependsOn},
      );

  Future<void> removeDependency(String orgId, String taskId, String depId) =>
      api.delete('${_org(orgId)}/tasks/$taskId/dependencies/$depId');

  // ------------------------------------------------------------ recurrence

  Future<TaskRecurrenceOut> setRecurrence(
    String orgId,
    String taskId, {
    required String unit,
    int count = 1,
  }) async =>
      TaskRecurrenceOut.fromJson(await _obj(api.post(
        '${_org(orgId)}/tasks/$taskId/recurrence',
        body: {'interval_unit': unit, 'interval_count': count},
      )));

  Future<void> stopRecurrence(String orgId, String taskId) =>
      api.post('${_org(orgId)}/tasks/$taskId/recurrence/stop');

  // ------------------------------------------------------- task reminders

  Future<List<ReminderOut>> taskReminders(String orgId, String taskId) =>
      api.getList('${_org(orgId)}/tasks/$taskId/reminders', ReminderOut.fromJson);

  Future<ReminderOut> addTaskReminder(
    String orgId,
    String taskId,
    ReminderIn body,
  ) async =>
      ReminderOut.fromJson(await _obj(
        api.post('${_org(orgId)}/tasks/$taskId/reminders', body: body.toJson()),
      ));

  // ------------------------------------------------------------------ tags

  Future<List<TagOut>> tags(String orgId) =>
      api.getList('${_org(orgId)}/tags', TagOut.fromJson);

  Future<TagOut> createTag(String orgId, String name) async => TagOut.fromJson(
        await _obj(api.post('${_org(orgId)}/tags', body: {'name': name})),
      );

  Future<void> tagTask(String orgId, String taskId, String tagId) =>
      api.post('${_org(orgId)}/tasks/$taskId/tags', body: {'tag_id': tagId});

  Future<void> untagTask(String orgId, String taskId, String tagId) =>
      api.delete('${_org(orgId)}/tasks/$taskId/tags/$tagId');

  // ============================================================= comments

  Future<ThreadOut> comments(String orgId, String taskId) async =>
      ThreadOut.fromJson(
        await api.getObject('${_org(orgId)}/tasks/$taskId/comments'),
      );

  Future<MessageOut> postComment(
    String orgId,
    String taskId,
    MessageIn body,
  ) async =>
      MessageOut.fromJson(await _obj(
        api.post('${_org(orgId)}/tasks/$taskId/comments', body: body.toJson()),
      ));

  Future<MessageOut> editComment(String orgId, String messageId, String body) async =>
      MessageOut.fromJson(await _obj(
        api.patch('${_org(orgId)}/comments/$messageId', body: {'body': body}),
      ));

  Future<void> deleteComment(String orgId, String messageId) =>
      api.delete('${_org(orgId)}/comments/$messageId');

  Future<ThreadOut> projectComments(String orgId, String projectId) async =>
      ThreadOut.fromJson(
        await api.getObject('${_org(orgId)}/projects/$projectId/comments'),
      );

  Future<MessageOut> postProjectComment(
    String orgId,
    String projectId,
    MessageIn body,
  ) async =>
      MessageOut.fromJson(await _obj(api.post(
        '${_org(orgId)}/projects/$projectId/comments',
        body: body.toJson(),
      )));

  // ========================================================== attachments

  /// Step 1: declare the file and get a presigned PUT plus **the content type
  /// to echo**. The signature covers `Content-Type` byte for byte, so the
  /// value the server returns is the only one that will work.
  Future<UploadTicket> createTaskAttachment(
    String orgId,
    String taskId, {
    required String filename,
    required String contentType,
  }) async =>
      UploadTicket.fromJson(await _obj(api.post(
        '${_org(orgId)}/tasks/$taskId/attachments',
        body: {'filename': filename, 'content_type': contentType},
      )));

  Future<UploadTicket> createProjectAttachment(
    String orgId,
    String projectId, {
    required String filename,
    required String contentType,
  }) async =>
      UploadTicket.fromJson(await _obj(api.post(
        '${_org(orgId)}/projects/$projectId/attachments',
        body: {'filename': filename, 'content_type': contentType},
      )));

  /// Step 3: the server HEADs the object, enforces the real size and flips the
  /// row to `ready`.
  Future<AttachmentOut> confirmAttachment(String orgId, String attachmentId) async =>
      AttachmentOut.fromJson(await _obj(
        api.post('${_org(orgId)}/attachments/$attachmentId/confirm'),
      ));

  Future<List<TaskFileOut>> taskFiles(String orgId, String taskId) =>
      api.getList('${_org(orgId)}/tasks/$taskId/files', TaskFileOut.fromJson);

  Future<UploadTicket> createTaskFile(
    String orgId,
    String taskId, {
    required String filename,
    required String contentType,
  }) async =>
      UploadTicket.fromJson(await _obj(api.post(
        '${_org(orgId)}/tasks/$taskId/files',
        body: {'filename': filename, 'content_type': contentType},
      )));

  Future<void> deleteTaskFile(String orgId, String taskId, String fileId) =>
      api.delete('${_org(orgId)}/tasks/$taskId/files/$fileId');

  // ============================================================ structure

  Future<List<ProjectOut>> projects(String orgId, {bool includeArchived = false}) =>
      api.getList(
        '${_org(orgId)}/projects',
        ProjectOut.fromJson,
        query: {if (includeArchived) 'include_archived': true},
      );

  Future<ProjectOut> project(String orgId, String projectId) async =>
      ProjectOut.fromJson(
        await api.getObject('${_org(orgId)}/projects/$projectId'),
      );

  Future<ProjectOut> createProject(String orgId, ProjectCreate body) async =>
      ProjectOut.fromJson(
        await _obj(api.post('${_org(orgId)}/projects', body: body.toJson())),
      );

  Future<List<ProjectGroupOut>> projectGroups(String orgId) =>
      api.getList('${_org(orgId)}/project-groups', ProjectGroupOut.fromJson);

  Future<List<MemberOut>> members(String orgId) =>
      api.getList('${_org(orgId)}/members', MemberOut.fromJson);

  Future<List<TeamOut>> teams(String orgId) =>
      api.getList('${_org(orgId)}/teams', TeamOut.fromJson);

  // =============================================================== screens

  Future<DashboardOut> dashboard(String orgId) async =>
      DashboardOut.fromJson(await api.getObject('${_org(orgId)}/dashboard'));

  Future<PlannerOut> planner(String orgId, {String? userId}) async =>
      PlannerOut.fromJson(await api.getObject(
        '${_org(orgId)}/planner',
        query: {'user_id': userId},
      ));

  Future<void> placeInPlanner(
    String orgId,
    String taskId, {
    required String bucket,
    int? position,
  }) =>
      api.put(
        '${_org(orgId)}/planner/$taskId',
        body: {'bucket': bucket, 'position': ?position},
      );

  Future<void> removeFromPlanner(String orgId, String taskId) =>
      api.delete('${_org(orgId)}/planner/$taskId');

  Future<CalendarOut> calendar(
    String orgId, {
    required DateTime start,
    required DateTime end,
  }) async =>
      CalendarOut.fromJson(await api.getObject(
        '${_org(orgId)}/calendar',
        query: {'start': fmtDay(start), 'end': fmtDay(end)},
      ));

  Future<SearchOut> search(String orgId, String query, {int limit = 20}) async =>
      SearchOut.fromJson(await api.getObject(
        '${_org(orgId)}/search',
        query: {'q': query, 'limit': limit},
      ));

  // -------------------------------------------------------------- bookmarks

  Future<List<BookmarkOut>> bookmarks(String orgId) =>
      api.getList('${_org(orgId)}/bookmarks', BookmarkOut.fromJson);

  Future<BookmarkOut> createBookmark(
    String orgId, {
    required String url,
    String description = '',
  }) async =>
      BookmarkOut.fromJson(await _obj(api.post(
        '${_org(orgId)}/bookmarks',
        body: {'url': url, 'description': description},
      )));

  Future<BookmarkOut> updateBookmark(
    String orgId,
    String id,
    Map<String, dynamic> patch,
  ) async =>
      BookmarkOut.fromJson(
        await _obj(api.patch('${_org(orgId)}/bookmarks/$id', body: patch)),
      );

  Future<void> deleteBookmark(String orgId, String id) =>
      api.delete('${_org(orgId)}/bookmarks/$id');

  Future<void> setBookmarkPinned(String orgId, String id, bool pinned) =>
      api.post('${_org(orgId)}/bookmarks/$id/pinned', body: {'pinned': pinned});

  // ------------------------------------------------------- personal notes

  Future<List<PersonalNoteOut>> notes(String orgId) =>
      api.getList('${_org(orgId)}/notes', PersonalNoteOut.fromJson);

  Future<PersonalNoteOut> createNote(
    String orgId, {
    required String title,
    String body = '',
  }) async =>
      PersonalNoteOut.fromJson(await _obj(api.post(
        '${_org(orgId)}/notes',
        body: {'title': title, 'body': body},
      )));

  Future<PersonalNoteOut> updateNote(
    String orgId,
    String id,
    Map<String, dynamic> patch,
  ) async =>
      PersonalNoteOut.fromJson(
        await _obj(api.patch('${_org(orgId)}/notes/$id', body: patch)),
      );

  Future<void> deleteNote(String orgId, String id) =>
      api.delete('${_org(orgId)}/notes/$id');

  // ======================================================= knowledge base

  Future<List<BookOut>> books(String orgId, {bool includeArchived = false}) =>
      api.getList(
        '${_org(orgId)}/kb/books',
        BookOut.fromJson,
        query: {if (includeArchived) 'include_archived': true},
      );

  Future<BookOut> book(String orgId, String bookId) async =>
      BookOut.fromJson(await api.getObject('${_org(orgId)}/kb/books/$bookId'));

  Future<List<ArticleOut>> articles(String orgId, String bookId) => api.getList(
        '${_org(orgId)}/kb/books/$bookId/articles',
        ArticleOut.fromJson,
      );

  Future<ArticleOut> article(String orgId, String articleId) async =>
      ArticleOut.fromJson(
        await api.getObject('${_org(orgId)}/kb/articles/$articleId'),
      );

  Future<List<RevisionOut>> articleRevisions(String orgId, String articleId) =>
      api.getList(
        '${_org(orgId)}/kb/articles/$articleId/revisions',
        RevisionOut.fromJson,
      );

  Future<RevisionOut> revision(String orgId, String revisionId) async =>
      RevisionOut.fromJson(
        await api.getObject('${_org(orgId)}/kb/revisions/$revisionId'),
      );

  /// Reading an article means fetching its current revision; the article row
  /// itself carries no body.
  Future<RevisionOut?> currentRevision(String orgId, String articleId) async {
    final revisions = await articleRevisions(orgId, articleId);
    for (final r in revisions) {
      if (r.isCurrent) return r;
    }
    return revisions.isEmpty ? null : revisions.first;
  }

  // ------------------------------------------------------------------ misc

  Future<InvitePreview> previewInvite(String token) async =>
      InvitePreview.fromJson(await api.getObject('/api/invites/$token'));

  Future<void> acceptInviteToken(String token) =>
      api.post('/api/invites/$token/accept');

  Future<Map<String, dynamic>> _obj(Future<dynamic> call) async {
    final raw = await call;
    return raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
  }
}

/// `yyyy-MM-dd` for query parameters.
String? fmtDay(DateTime? d) {
  if (d == null) return null;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

int? asIntish(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

final repoProvider = Provider<Repo>((ref) => Repo(ref.watch(apiProvider)));
