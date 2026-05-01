import 'dart:async';

class _QueuedRequest<T> {
  final Future<T> Function() task;
  final Completer<T> completer;
  final String description;
  final DateTime queuedAt;

  _QueuedRequest({
    required this.task,
    required this.completer,
    required this.description,
  }) : queuedAt = DateTime.now();
}

class NetworkRequestQueue {
  static final NetworkRequestQueue _instance = NetworkRequestQueue._internal();
  factory NetworkRequestQueue() => _instance;
  NetworkRequestQueue._internal();

  final List<_QueuedRequest<dynamic>> _pending = [];

  int get pendingCount => _pending.length;
  bool get isEmpty => _pending.isEmpty;

  void enqueue<T>({
    required Future<T> Function() task,
    required Completer<T> completer,
    required String description,
  }) {
    _pending.add(
      _QueuedRequest<T>(
        task: task,
        completer: completer,
        description: description,
      ),
    );
    print('📥 NetworkRequestQueue: encolada "$description" (total: ${_pending.length})');
  }

  Future<void> retryAll() async {
    if (_pending.isEmpty) {
      print('📤 NetworkRequestQueue: nada que reintentar');
      return;
    }

    print('🔁 NetworkRequestQueue: reintentando ${_pending.length} peticiones...');
    final snapshot = List<_QueuedRequest<dynamic>>.from(_pending);
    _pending.clear();

    for (final req in snapshot) {
      try {
        final result = await req.task();
        if (!req.completer.isCompleted) {
          req.completer.complete(result);
        }
        print('✅ NetworkRequestQueue: éxito en "${req.description}"');
      } catch (e, st) {
        print('⚠️ NetworkRequestQueue: falló de nuevo "${req.description}": $e');
        if (_isNetworkError(e)) {
          _pending.add(req);
        } else {
          if (!req.completer.isCompleted) {
            req.completer.completeError(e, st);
          }
        }
      }
    }

    print('📊 NetworkRequestQueue: ${_pending.length} pendientes tras reintento');
  }

  void rejectAll(Object reason) {
    if (_pending.isEmpty) return;
    print('🚫 NetworkRequestQueue: rechazando ${_pending.length} peticiones (razón: $reason)');
    final snapshot = List<_QueuedRequest<dynamic>>.from(_pending);
    _pending.clear();
    for (final req in snapshot) {
      if (!req.completer.isCompleted) {
        req.completer.completeError(reason);
      }
    }
  }

  void clear() {
    _pending.clear();
  }

  static bool _isNetworkError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection') ||
        msg.contains('network');
  }
}
