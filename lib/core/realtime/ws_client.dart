import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_controller.dart';

/// What the socket is watching. Access is checked at *watch* time.
class Watch {
  const Watch(this.kind, this.id);

  final String kind;
  final String id;

  static Watch task(String id) => Watch('task', id);

  /// Watching the organisation is how you follow a board: one watch instead of
  /// one per card.
  static Watch organisation(String id) => Watch('org', id);

  Map<String, dynamic> get message => {
        'watch': {'kind': kind, 'id': id},
      };

  @override
  bool operator ==(Object other) =>
      other is Watch && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// A nudge from the server. Events never carry bodies.
class RealtimeEvent {
  const RealtimeEvent(this.type, this.raw);

  final String type;
  final Map<String, dynamic> raw;

  String? get taskId => raw['task_id'] as String?;
  String? get organisationId => raw['organisation_id'] as String?;
}

/// The realtime socket, authenticated with the profile's personal access
/// token.
///
/// `WS /api/ws` accepts exactly two credentials: an `sAccessToken` cookie or a
/// PAT in an Authorization header. A header-mode mobile client has neither —
/// its SuperTokens access token is *not* a PAT — so sign-in mints one and the
/// socket uses that.
///
/// Events are deliberately content-free, so every nudge means "refetch over
/// HTTP". Nudges are coalesced for 1.5s the way the web client does, because a
/// burst of edits should cost one refetch, not ten.
class RealtimeClient {
  RealtimeClient({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _coalesce;
  Timer? _reconnect;
  bool _disposed = false;
  int _attempt = 0;

  final Set<Watch> _watches = {};
  final _nudges = StreamController<Set<String>>.broadcast();

  /// Fires at most every 1.5s with the set of watch ids that changed.
  Stream<Set<String>> get nudges => _nudges.stream;

  final Set<String> _pending = {};

  Uri get _uri {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/ws',
    );
  }

  void connect() {
    if (_disposed || _channel != null || token.isEmpty) return;
    try {
      final channel = IOWebSocketChannel.connect(
        _uri,
        headers: {'Authorization': 'Bearer $token'},
        pingInterval: const Duration(seconds: 30),
      );
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _attempt = 0;
      for (final w in _watches) {
        _send(w.message);
      }
    } catch (_) {
      _scheduleReconnect();
    }
  }

  /// Realtime is a nicety; if it will not connect the app still works by
  /// pull-to-refresh, so failures back off quietly rather than surfacing.
  void _scheduleReconnect() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (_disposed) return;
    _reconnect?.cancel();
    final delay = Duration(seconds: (1 << _attempt.clamp(0, 5)).clamp(1, 60));
    _attempt++;
    _reconnect = Timer(delay, connect);
  }

  void watch(Watch w) {
    if (!_watches.add(w)) return;
    _send(w.message);
  }

  void unwatch(Watch w) => _watches.remove(w);

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return;
      decoded = parsed.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    final id = decoded['task_id'] ?? decoded['id'] ?? decoded['organisation_id'];
    if (id is String) _pending.add(id);
    final type = decoded['type'];
    if (type is String) _pending.add(type);

    _coalesce ??= Timer(const Duration(milliseconds: 1500), () {
      _coalesce = null;
      if (_pending.isEmpty || _nudges.isClosed) return;
      _nudges.add(Set.of(_pending));
      _pending.clear();
    });
  }

  void dispose() {
    _disposed = true;
    _coalesce?.cancel();
    _reconnect?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _nudges.close();
  }
}

/// The socket for the active profile, or null when it has no token yet.
///
/// Realtime is optional: a profile whose PAT could not be minted simply has no
/// socket, and every screen still refetches on demand.
final realtimeProvider = Provider<RealtimeClient?>((ref) {
  final state = ref.watch(authControllerProvider);
  final profile = state.activeProfile;
  final token = profile?.patForSocket;
  if (profile == null || token == null || token.isEmpty) return null;

  final client = RealtimeClient(baseUrl: profile.baseUrl, token: token);
  client.connect();
  ref.onDispose(client.dispose);
  return client;
});
