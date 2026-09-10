import 'dart:convert';
import 'dart:typed_data';

import 'package:ayeaye_mobile/core/api/api_client.dart';
import 'package:ayeaye_mobile/core/api/api_exception.dart';
import 'package:ayeaye_mobile/core/api/repo.dart';
import 'package:ayeaye_mobile/core/auth/session_tokens.dart';
import 'package:ayeaye_mobile/core/models/enums.dart';
import 'package:ayeaye_mobile/core/upload/uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;

    if (path.endsWith('/attachments')) {
      return _json({
        'attachment': {
          'id': 'att-1',
          'filename': 'voice-note.m4a',
          'content_type': 'audio/mp4',
          'size_bytes': 0,
          'url': 'https://storage.example.test/att-1',
        },
        'upload_url': 'https://storage.example.test/put/att-1?X-Amz-Signature=x',
        // The server normalises and signs *this* value, and hands it back for
        // the client to echo.
        'content_type': 'audio/mp4',
      });
    }
    if (path.contains('/attachments/') && path.endsWith('/confirm')) {
      return _json({
        'id': 'att-1',
        'filename': 'voice-note.m4a',
        'content_type': 'audio/mp4',
        'size_bytes': 2048,
        'url': 'https://storage.example.test/att-1',
      });
    }
    // The presigned PUT.
    return ResponseBody.fromString('', 200);
  }

  static ResponseBody _json(Object value) => ResponseBody.fromString(
        jsonEncode(value),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late Uploader uploader;

  setUp(() {
    adapter = _Adapter();
    uploader = Uploader(Repo(ApiClient(
      baseUrl: 'https://tasks.example.test',
      tokens: const SessionTokens(accessToken: 'access-1'),
      dio: Dio()..httpClientAdapter = adapter,
      storageDio: Dio(BaseOptions(validateStatus: (_) => true))
        ..httpClientAdapter = adapter,
    )));
  });

  test('runs declare, PUT to storage, then confirm — in that order', () async {
    final result = await uploader.uploadTaskAttachment(
      orgId: 'o1',
      taskId: 't1',
      file: const PendingUpload(
        filename: 'voice-note.m4a',
        contentType: 'audio/mp4',
        bytes: [1, 2, 3, 4],
      ),
    );

    expect(result.id, 'att-1');
    expect(
      adapter.requests.map((r) => '${r.method} ${r.path}').toList(),
      [
        'POST /api/organisations/o1/tasks/t1/attachments',
        'PUT https://storage.example.test/put/att-1?X-Amz-Signature=x',
        'POST /api/organisations/o1/attachments/att-1/confirm',
      ],
    );
  });

  test('echoes the content type the server signed, not the one we guessed',
      () async {
    await uploader.uploadTaskAttachment(
      orgId: 'o1',
      taskId: 't1',
      file: const PendingUpload(
        filename: 'voice-note.m4a',
        // What the platform would call it. The server normalises this and
        // signs the normalised value; sending our own fails with
        // SignatureDoesNotMatch, which says nothing about content types.
        contentType: 'audio/mp4;codecs=aac',
        bytes: [1, 2, 3, 4],
      ),
    );

    final declare = adapter.requests.first;
    expect((declare.data as Map)['content_type'], 'audio/mp4;codecs=aac',
        reason: 'we declare what we have');

    final put = adapter.requests[1];
    expect(put.headers['Content-Type'], 'audio/mp4',
        reason: "the PUT must use the server's normalised value");
  });

  test('the storage PUT carries no session credentials', () async {
    await uploader.uploadTaskAttachment(
      orgId: 'o1',
      taskId: 't1',
      file: const PendingUpload(
        filename: 'a.png',
        contentType: 'image/png',
        bytes: [1, 2, 3],
      ),
    );

    expect(adapter.requests[1].headers.containsKey('Authorization'), isFalse);
  });

  test('refuses an oversized file before uploading it', () async {
    // The real size is enforced at confirm, so without a local check a
    // too-large file fails only after the whole upload has been sent.
    await expectLater(
      uploader.uploadTaskAttachment(
        orgId: 'o1',
        taskId: 't1',
        file: PendingUpload(
          filename: 'huge.mp4',
          contentType: 'video/mp4',
          bytes: List.filled(maxUploadBytes + 1, 0),
        ),
      ),
      throwsA(isA<ApiError>().having(
        (e) => e.message,
        'message',
        contains('over the'),
      )),
    );
    expect(adapter.requests, isEmpty, reason: 'nothing was sent');
  });

  test('refuses an empty file', () async {
    await expectLater(
      uploader.uploadTaskAttachment(
        orgId: 'o1',
        taskId: 't1',
        file: const PendingUpload(
          filename: 'empty.txt',
          contentType: 'text/plain',
          bytes: [],
        ),
      ),
      throwsA(isA<ApiError>()),
    );
    expect(adapter.requests, isEmpty);
  });

  group('content types', () {
    test('maps the extensions the API allows', () {
      expect(contentTypeForPath('note.m4a'), 'audio/mp4');
      expect(contentTypeForPath('shot.JPG'), 'image/jpeg');
      expect(contentTypeForPath('doc.pdf'), 'application/pdf');
      expect(contentTypeForPath('clip.webm'), 'video/webm');
    });

    test('does not claim a type for HEIC', () {
      // `image/heic` is not on the allow-list and it is the iPhone camera's
      // default, so it must fall through to conversion rather than be
      // declared and rejected.
      expect(contentTypeForPath('IMG_0001.heic'), isNull);
      expect(allowedUploadTypes.contains('image/heic'), isFalse);
    });

    test('every type it maps is one the API accepts', () {
      for (final ext in ['jpg', 'png', 'gif', 'webp', 'pdf', 'txt', 'csv',
        'mp4', 'webm', 'm4a', 'mp3']) {
        final type = contentTypeForPath('file.$ext');
        expect(type, isNotNull, reason: ext);
        expect(allowedUploadTypes, contains(type), reason: ext);
      }
    });

    test('classifies audio and images for the right player', () {
      expect(isAudio('audio/mp4'), isTrue);
      expect(isImage('image/webp'), isTrue);
      expect(isAudio('video/mp4'), isFalse);
    });
  });
}
