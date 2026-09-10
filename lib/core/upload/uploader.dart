import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/repo.dart';
import '../models/enums.dart';
import '../models/models.dart';

/// A file on its way to an attachment row.
class PendingUpload {
  const PendingUpload({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String filename;

  /// What *we* think it is. The server normalises and re-signs, and its answer
  /// is what actually goes on the wire.
  final String contentType;

  final List<int> bytes;

  int get sizeBytes => bytes.length;
}

/// Runs the three-step upload: declare, PUT to storage, confirm.
///
/// Bytes go client → storage directly and never through the API.
class Uploader {
  const Uploader(this.repo);

  final Repo repo;

  ApiClient get _api => repo.api;

  /// Attaches a file to a task's comment composer (an attachment row that a
  /// message can then reference).
  Future<AttachmentOut> uploadTaskAttachment({
    required String orgId,
    required String taskId,
    required PendingUpload file,
  }) =>
      _run(
        file,
        () => repo.createTaskAttachment(
          orgId,
          taskId,
          filename: file.filename,
          contentType: file.contentType,
        ),
        orgId,
      );

  /// Attaches a file to the task itself, rather than to a comment.
  Future<AttachmentOut> uploadTaskFile({
    required String orgId,
    required String taskId,
    required PendingUpload file,
  }) =>
      _run(
        file,
        () => repo.createTaskFile(
          orgId,
          taskId,
          filename: file.filename,
          contentType: file.contentType,
        ),
        orgId,
      );

  Future<AttachmentOut> _run(
    PendingUpload file,
    Future<UploadTicket> Function() declare,
    String orgId,
  ) async {
    // The real size is enforced at confirm, so checking here turns a wasted
    // 50MB upload into an instant, explainable refusal.
    if (file.sizeBytes > maxUploadBytes) {
      throw ApiError(
        '${file.filename} is ${_mb(file.sizeBytes)}, over the '
        '${_mb(maxUploadBytes)} limit',
      );
    }
    if (file.sizeBytes == 0) {
      throw ApiError('${file.filename} is empty');
    }

    final ticket = await declare();

    // Echo the server's content type verbatim: the signature covers it byte
    // for byte, and a mismatch fails as `SignatureDoesNotMatch`, which says
    // nothing at all about content types.
    await _api.putToStorage(
      uploadUrl: ticket.uploadUrl,
      bytes: file.bytes,
      contentType: ticket.contentType,
    );

    return repo.confirmAttachment(orgId, ticket.attachment.id);
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

/// Reads a picked image and hands back something the API will accept.
///
/// `image/heic` is not on the allow-list and it is the iPhone camera's
/// default, so anything that is not already an allowed type is re-encoded as
/// JPEG — which is better for size on a phone connection anyway.
Future<PendingUpload> prepareImage(File source) async {
  final declared = contentTypeForPath(source.path);
  final rawName = source.uri.pathSegments.last;

  if (declared != null && allowedUploadTypes.contains(declared)) {
    return PendingUpload(
      filename: rawName,
      contentType: declared,
      bytes: await source.readAsBytes(),
    );
  }

  final dir = await getTemporaryDirectory();
  final target = '${dir.path}/converted_${DateTime.now().microsecondsSinceEpoch}.jpg';
  final converted = await FlutterImageCompress.compressAndGetFile(
    source.absolute.path,
    target,
    quality: 88,
    format: CompressFormat.jpeg,
    // Phone cameras produce far more pixels than any of these screens shows;
    // capping the long edge keeps uploads quick without visible loss.
    minWidth: 2048,
    minHeight: 2048,
  );
  if (converted == null) {
    throw const ApiError('That image could not be converted for upload');
  }
  return PendingUpload(
    filename: _withExtension(rawName, 'jpg'),
    contentType: 'image/jpeg',
    bytes: await File(converted.path).readAsBytes(),
  );
}

/// A finished voice note.
///
/// The recorder is configured for AAC-in-MP4, which the allow-list covers as
/// `audio/mp4`.
Future<PendingUpload> prepareVoiceNote(File source, {String? label}) async {
  final bytes = await source.readAsBytes();
  final ext = source.path.split('.').last.toLowerCase();
  final type = contentTypeForPath(source.path) ?? 'audio/mp4';
  final stamp = DateTime.now();
  final name = label ??
      'voice-note-${stamp.year}${_two(stamp.month)}${_two(stamp.day)}'
          '-${_two(stamp.hour)}${_two(stamp.minute)}${_two(stamp.second)}.$ext';
  return PendingUpload(filename: name, contentType: type, bytes: bytes);
}

String _two(int v) => v.toString().padLeft(2, '0');

String _withExtension(String name, String ext) {
  final dot = name.lastIndexOf('.');
  final stem = dot <= 0 ? name : name.substring(0, dot);
  return '$stem.$ext';
}

/// Best-effort type from a file extension. The server has the final say.
String? contentTypeForPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'mp4' => 'video/mp4',
    'webm' => 'video/webm',
    'm4a' || 'aac' || 'mp4a' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    _ => null,
  };
}

bool isAudio(String contentType) => contentType.startsWith('audio/');
bool isImage(String contentType) => contentType.startsWith('image/');

final uploaderProvider =
    Provider<Uploader>((ref) => Uploader(ref.watch(repoProvider)));
