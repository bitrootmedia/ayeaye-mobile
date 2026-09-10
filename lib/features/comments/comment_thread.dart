import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../core/upload/uploader.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/rich_body.dart';
import '../../ui/widgets/states.dart';
import '../tasks/task_providers.dart';
import 'voice_note.dart';

/// A task's conversation.
///
/// Rendered inline in the detail screen rather than on its own page: on a
/// phone, a comment almost always needs the task's title and status in view to
/// make sense.
class CommentThread extends ConsumerWidget {
  const CommentThread({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(taskCommentsProvider(taskId));
    return AsyncView(
      value: thread,
      onRetry: () => ref.invalidate(taskCommentsProvider(taskId)),
      loading: const Padding(
        padding: EdgeInsets.all(Gap.xl),
        child: LoadingView(),
      ),
      data: (data) {
        final visible = data.messages;
        if (visible.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.lg,
            ),
            child: Text(
              'No comments yet.',
              style: context.texts.muted,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final message in visible)
              CommentBubble(message: message, taskId: taskId),
          ],
        );
      },
    );
  }
}

class CommentBubble extends ConsumerWidget {
  const CommentBubble({super.key, required this.message, required this.taskId});

  final MessageOut message;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (message.deleted) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.sm,
        ),
        child: Text(
          'A comment was deleted.',
          style: context.texts.small.copyWith(
            color: context.colors.mutedForeground,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final baseUrl = ref.watch(repoProvider).api.baseUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonAvatar(person: message.author, size: 30),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        message.mine
                            ? 'You'
                            : Fmt.person(
                                message.author?.displayName,
                                message.author?.email,
                              ),
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.small.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Text(
                      _timestamp(message.createdAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.colors.mutedForeground,
                      ),
                    ),
                    if (message.editedAt != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '· edited',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.colors.mutedForeground,
                        ),
                      ),
                    ],
                    if (message.mine) ...[
                      const Spacer(),
                      ShadIconButton.ghost(
                        width: 24,
                        height: 24,
                        icon: const Icon(LucideIcons.trash2, size: 13),
                        onPressed: () => _delete(context, ref),
                      ),
                    ],
                  ],
                ),
                if (message.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  RichBody(message.body, baseUrl: baseUrl),
                ],
                for (final attachment in message.attachments) ...[
                  const SizedBox(height: Gap.sm),
                  AttachmentTile(attachment: attachment),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `created_at` arrives as a plain string on messages rather than a typed
  /// timestamp, so this copes with either.
  static String _timestamp(String raw) {
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : Fmt.ago(parsed.toLocal());
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete this comment?'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final orgId = ref.read(requireOrgIdProvider);
    await runGuarded(
      context,
      () => ref.read(repoProvider).deleteComment(orgId, message.id),
      success: 'Deleted',
    );
    ref.invalidate(taskCommentsProvider(taskId));
  }
}

/// One attachment: a voice note gets a player, an image gets a thumbnail, and
/// everything else gets a row.
class AttachmentTile extends ConsumerWidget {
  const AttachmentTile({super.key, required this.attachment});

  final AttachmentOut attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isAudio(attachment.contentType)) {
      return VoiceNotePlayer(
        url: attachment.url,
        filename: attachment.filename,
        sizeBytes: attachment.sizeBytes,
      );
    }
    if (isImage(attachment.contentType)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: Image.network(
            attachment.thumbnailUrl ?? attachment.url,
            fit: BoxFit.cover,
            errorBuilder: (context, _, _) => _FileRow(
              filename: attachment.filename,
              sizeBytes: attachment.sizeBytes,
            ),
          ),
        ),
      );
    }
    return _FileRow(
      filename: attachment.filename,
      sizeBytes: attachment.sizeBytes,
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.filename, required this.sizeBytes});

  final String filename;
  final int sizeBytes;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(Gap.sm),
        decoration: BoxDecoration(
          color: context.colors.muted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.paperclip,
              size: 14,
              color: context.colors.mutedForeground,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                filename,
                overflow: TextOverflow.ellipsis,
                style: context.texts.small,
              ),
            ),
            Text(
              Fmt.fileSize(sizeBytes),
              style: TextStyle(
                fontSize: 10.5,
                color: context.colors.mutedForeground,
              ),
            ),
          ],
        ),
      );
}

/// The composer: text, a photo, or a voice note.
///
/// Attachments are uploaded *before* the message is posted, because a message
/// references attachment rows by id — so the mic and camera buttons resolve to
/// ids that the send button then attaches.
class CommentComposer extends ConsumerStatefulWidget {
  const CommentComposer({super.key, required this.taskId, this.canPost = true});

  final String taskId;
  final bool canPost;

  @override
  ConsumerState<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<CommentComposer> {
  final _controller = TextEditingController();
  final _pending = <AttachmentOut>[];
  bool _recording = false;
  bool _busy = false;
  String? _uploadingLabel;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _upload(PendingUpload file, String label) async {
    setState(() => _uploadingLabel = label);
    try {
      final orgId = ref.read(requireOrgIdProvider);
      final attachment = await ref.read(uploaderProvider).uploadTaskAttachment(
            orgId: orgId,
            taskId: widget.taskId,
            file: file,
          );
      if (!mounted) return;
      setState(() {
        _pending.add(attachment);
        _uploadingLabel = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingLabel = null);
      showErrorToast(context, error, title: 'Upload failed');
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Requested large: the server caps at 50MB and `prepareImage` re-encodes
      // to JPEG anyway, which is also how HEIC gets handled.
      maxWidth: 3000,
      maxHeight: 3000,
    );
    if (picked == null || !mounted) return;
    try {
      final prepared = await prepareImage(File(picked.path));
      await _upload(prepared, prepared.filename);
    } catch (error) {
      if (mounted) showErrorToast(context, error, title: 'Upload failed');
    }
  }

  Future<void> _onRecorded(File file, Duration length) async {
    setState(() => _recording = false);
    try {
      final prepared = await prepareVoiceNote(file);
      await _upload(prepared, 'Voice note ${Fmt.stopwatch(length)}');
    } catch (error) {
      if (mounted) showErrorToast(context, error, title: 'Upload failed');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;
    setState(() => _busy = true);

    final orgId = ref.read(requireOrgIdProvider);
    try {
      await ref.read(repoProvider).postComment(
            orgId,
            widget.taskId,
            MessageIn(
              // A message needs a body, so an attachment posted on its own
              // gets a short one rather than failing validation.
              body: text.isEmpty
                  ? (_pending.any((a) => isAudio(a.contentType))
                      ? 'Voice note'
                      : 'Attachment')
                  : text,
              attachmentIds: _pending.map((a) => a.id).toList(),
            ),
          );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _pending.clear();
        _busy = false;
      });
      ref.invalidate(taskCommentsProvider(widget.taskId));
      ref.invalidate(taskFilesProvider(widget.taskId));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorToast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canPost) {
      return Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: context.colors.card,
          border: Border(top: BorderSide(color: context.colors.border)),
        ),
        child: Text(
          'You cannot comment on this task.',
          style: context.texts.muted,
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_recording) {
      return VoiceRecorderBar(
        onFinished: _onRecorded,
        onCancelled: () => setState(() => _recording = false),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_uploadingLabel != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: Gap.md,
                  right: Gap.md,
                  top: Gap.sm,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        'Uploading ${_uploadingLabel!}…',
                        style: context.texts.small,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (_pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  left: Gap.md,
                  right: Gap.md,
                  top: Gap.sm,
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final attachment in _pending)
                      _PendingChip(
                        attachment: attachment,
                        onRemove: () =>
                            setState(() => _pending.remove(attachment)),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.mic, size: 19),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _recording = true),
                  ),
                  ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.image, size: 19),
                    onPressed: _busy ? null : _pickImage,
                  ),
                  Expanded(
                    child: ShadInput(
                      controller: _controller,
                      placeholder: const Text('Write a comment'),
                      maxLines: 5,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  ShadIconButton(
                    icon: _busy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.arrowUp, size: 18),
                    onPressed: _busy ||
                            (_controller.text.trim().isEmpty && _pending.isEmpty)
                        ? null
                        : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.attachment, required this.onRemove});

  final AttachmentOut attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(left: Gap.sm, right: 2, top: 2, bottom: 2),
        decoration: BoxDecoration(
          color: context.colors.muted,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAudio(attachment.contentType)
                  ? LucideIcons.audioLines
                  : isImage(attachment.contentType)
                      ? LucideIcons.image
                      : LucideIcons.paperclip,
              size: 12,
              color: context.colors.mutedForeground,
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                attachment.filename,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            ShadIconButton.ghost(
              width: 22,
              height: 22,
              icon: const Icon(LucideIcons.x, size: 12),
              onPressed: onRemove,
            ),
          ],
        ),
      );
}
