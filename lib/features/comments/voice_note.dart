import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../ui/format.dart';
import '../../ui/theme.dart';

/// Records a voice note.
///
/// Encoded as AAC in an MP4 container, which the upload allow-list covers as
/// `audio/mp4` — the platform's own default for iOS voice memos, and one of
/// the few audio types the server will sign.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({
    super.key,
    required this.onFinished,
    required this.onCancelled,
  });

  final void Function(File file, Duration length) onFinished;
  final VoidCallback onCancelled;

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _recorder = AudioRecorder();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  String? _path;
  bool _starting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() {
          _error = 'Microphone access is off for this app';
          _starting = false;
        });
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          // Speech, not music: mono at 32kbps keeps a two-minute note well
          // under a megabyte, which matters on a phone connection.
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _path = path;
        _starting = false;
      });
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not start recording: $error';
        _starting = false;
      });
    }
  }

  Future<void> _stop({required bool keep}) async {
    _ticker?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    final file = path == null ? null : File(path);

    if (!keep || file == null || !file.existsSync()) {
      if (file != null && file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {/* a stray temp file is harmless */}
      }
      widget.onCancelled();
      return;
    }
    widget.onFinished(file, _elapsed);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(Gap.md),
        color: context.colors.destructive.withValues(alpha: 0.08),
        child: Row(
          children: [
            Icon(
              LucideIcons.micOff,
              size: 16,
              color: context.colors.destructive,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                _error!,
                style: context.texts.small.copyWith(
                  color: context.colors.destructive,
                ),
              ),
            ),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: widget.onCancelled,
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        children: [
          _PulsingDot(active: !_starting),
          const SizedBox(width: Gap.md),
          Text(
            _starting ? 'Starting…' : Fmt.stopwatch(_elapsed),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: context.colors.foreground,
            ),
          ),
          const Spacer(),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => _stop(keep: false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: Gap.xs),
          ShadButton(
            size: ShadButtonSize.sm,
            onPressed: _starting ? null : () => _stop(keep: true),
            leading: const Icon(LucideIcons.check, size: 14),
            child: const Text('Attach'),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.active});

  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: widget.active
            ? Tween(begin: 0.35, end: 1.0).animate(_controller)
            : const AlwaysStoppedAnimation(0.4),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: context.colors.destructive,
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// Plays a voice note straight from its presigned URL.
///
/// Read URLs are minted fresh per read and expire, so nothing is cached and
/// the player always uses the URL the current fetch handed it.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.url,
    required this.filename,
    this.sizeBytes,
  });

  final String url;
  final String filename;
  final int? sizeBytes;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = AudioPlayer();
  bool _loaded = false;
  bool _failed = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_failed) return;
    try {
      if (!_loaded) {
        await _player.setUrl(widget.url);
        _loaded = true;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.sm,
          vertical: Gap.sm,
        ),
        decoration: BoxDecoration(
          color: context.colors.muted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                final buffering =
                    snapshot.data?.processingState == ProcessingState.loading ||
                        snapshot.data?.processingState ==
                            ProcessingState.buffering;
                return ShadIconButton(
                  width: 34,
                  height: 34,
                  onPressed: _toggle,
                  icon: buffering
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _failed
                              ? LucideIcons.circleAlert
                              : playing
                                  ? LucideIcons.pause
                                  : LucideIcons.play,
                          size: 15,
                        ),
                );
              },
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.audioLines,
                        size: 13,
                        color: context.colors.mutedForeground,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _failed ? 'Could not play this note' : 'Voice note',
                        style: context.texts.small.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, snapshot) {
                      final total = _player.duration;
                      final position = snapshot.data ?? Duration.zero;
                      final progress = (total == null || total.inMilliseconds == 0)
                          ? 0.0
                          : (position.inMilliseconds / total.inMilliseconds)
                              .clamp(0.0, 1.0);
                      return Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor: context.colors.border,
                                color: context.colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: Gap.sm),
                          Text(
                            total == null
                                ? (widget.sizeBytes == null
                                    ? ''
                                    : Fmt.fileSize(widget.sizeBytes!))
                                : Fmt.stopwatch(total - position),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: context.colors.mutedForeground,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
