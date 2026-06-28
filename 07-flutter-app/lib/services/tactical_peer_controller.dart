import 'dart:async';
import 'package:rxdart/rxdart.dart';

class TacticalPeerController {
  final _rawController = StreamController<Map<String, dynamic>>();
  final Map<String, Map<String, dynamic>> _cache = {};

  Stream<List<Map<String, dynamic>>> get optimizedPeerStream {
    return _rawController.stream
        .bufferTime(const Duration(milliseconds: 800))
        .map((List<Map<String, dynamic>> packets) {
          for (var peer in packets) {
            final id = peer['id'] as String;
            if (_cache.containsKey(id)) {
              final existing = _cache[id]!;
              final existingRssi = (existing['rssi'] as num?)?.toInt() ?? -90;
              final newRssi = (peer['rssi'] as num?)?.toInt() ?? -90;
              final smoothedRssi = ((existingRssi * 0.7) + (newRssi * 0.3)).round();
              _cache[id] = Map<String, dynamic>.from(peer)
                ..['rssi'] = smoothedRssi
                ..['lastSeen'] = DateTime.now().millisecondsSinceEpoch;
            } else {
              _cache[id] = Map<String, dynamic>.from(peer)
                ..['lastSeen'] = DateTime.now().millisecondsSinceEpoch;
            }
          }

          // Dead node pruning: eliminar nodos sin señal por más de 15 segundos
          final now = DateTime.now().millisecondsSinceEpoch;
          _cache.removeWhere((_, v) {
            final lastSeen = v['lastSeen'] as int? ?? 0;
            return (now - lastSeen) > 15000;
          });

          // Ordenar por RSSI descendente (señal más fuerte primero)
          final sorted = _cache.values.toList()
            ..sort((a, b) {
              final rssiA = (a['rssi'] as num?)?.toInt() ?? -90;
              final rssiB = (b['rssi'] as num?)?.toInt() ?? -90;
              return rssiB.compareTo(rssiA);
            });
          return sorted;
        })
        .distinct();
  }

  void addRawPeer(Map<String, dynamic> peer) {
    if (!_rawController.isClosed) {
      _rawController.add(peer);
    }
  }

  void clearCache() {
    _cache.clear();
  }

  void dispose() {
    _rawController.close();
  }
}
