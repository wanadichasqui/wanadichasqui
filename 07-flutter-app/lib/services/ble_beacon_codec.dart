// Copyright (C) 2026 Juan Carlos Diaz Parisca / Wanadi Tactical
//
// This file is part of Wanadi Chasqui.
//
// Wanadi Chasqui is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License version 3
// as published by the Free Software Foundation.
//
// Wanadi Chasqui is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See <https://www.gnu.org/licenses/> for more details.

/// Connectionless BLE-advertisement mesh beacons for emergency SOS.
///
/// Faithful Dart port of `01-wire-protocol/src/ble_beacon.rs` (validated by its
/// 8 Rust unit tests, kept as the canonical spec). When the Rust↔Flutter bridge
/// is wired (see tech-debt task), these calls move to the native crypto core.
///
/// Wire layout is byte-identical to the Rust version so a future native node
/// and a Dart node interoperate over the air.
import 'dart:convert';
import 'dart:typed_data';

/// Priority of an emergency beacon. Higher floods first / lives longer.
const int kPrioritySafe = 0; // "estoy a salvo"
const int kPriorityHelp = 1; // necesito ayuda
const int kPriorityCritical = 2; // SOS crítico (atrapado / herido)

/// Wire-format version. Must match the Rust `SOS_VERSION`.
const int _sosVersion = 1;

/// Max note length in bytes.
const int _maxNoteLen = 80;

/// Frame header size: msgId(4) + total(1) + index(1).
const int _frameHeader = 6;

/// Sentinel for "no GPS fix" (matches Rust i32::MIN).
const int _i32Min = -2147483648;

/// A decoded emergency beacon.
class SosBeacon {
  /// Random per-message id; groups fragments and powers dedup.
  final int msgId;

  /// Hops remaining; decremented on each relay, dropped at 0.
  final int ttl;

  /// One of kPriority*.
  final int priority;

  /// First 4 bytes of the sender identity (short, non-reversible id).
  final Uint8List senderId;

  /// Latitude in micro-degrees (degrees * 1e6). _i32Min = unknown.
  final int latMicro;

  /// Longitude in micro-degrees. _i32Min = unknown.
  final int lonMicro;

  /// Short human note (UTF-8, <= _maxNoteLen bytes).
  final String note;

  SosBeacon({
    required this.msgId,
    required this.ttl,
    required this.priority,
    required this.senderId,
    required this.latMicro,
    required this.lonMicro,
    required this.note,
  });

  bool get hasLocation => latMicro != _i32Min && lonMicro != _i32Min;

  double? get latitude => hasLocation ? latMicro / 1e6 : null;
  double? get longitude => hasLocation ? lonMicro / 1e6 : null;

  /// Returns a copy with the ttl decremented for relaying, or null when the
  /// beacon has expired and must not be re-advertised.
  SosBeacon? relayed() {
    if (ttl == 0) return null;
    final next = ttl - 1;
    if (next == 0) return null;
    return SosBeacon(
      msgId: msgId,
      ttl: next,
      priority: priority,
      senderId: senderId,
      latMicro: latMicro,
      lonMicro: lonMicro,
      note: note,
    );
  }
}

/// Encode a beacon to its compact wire form.
///
/// Layout (big-endian):
///   ver(1) msgId(4) ttl(1) priority(1) senderId(4) lat(4) lon(4) noteLen(1) note(..)
Uint8List encodeSos(SosBeacon b) {
  final noteBytes = utf8.encode(b.note);
  final noteLen = noteBytes.length > _maxNoteLen ? _maxNoteLen : noteBytes.length;

  final out = BytesBuilder();
  out.addByte(_sosVersion);
  out.add(_u32be(b.msgId));
  out.addByte(b.ttl & 0xFF);
  out.addByte(b.priority & 0xFF);
  out.add(_sender4(b.senderId));
  out.add(_i32be(b.latMicro));
  out.add(_i32be(b.lonMicro));
  out.addByte(noteLen);
  out.add(noteBytes.sublist(0, noteLen));
  return out.toBytes();
}

/// Decode a beacon from its wire form. Returns null on malformed input.
SosBeacon? decodeSos(Uint8List raw) {
  if (raw.length < 20) return null;
  if (raw[0] != _sosVersion) return null;

  final msgId = _readU32be(raw, 1);
  final ttl = raw[5];
  final priority = raw[6];
  final senderId = Uint8List.fromList(raw.sublist(7, 11));
  final latMicro = _readI32be(raw, 11);
  final lonMicro = _readI32be(raw, 15);
  final noteLen = raw[19];

  const noteStart = 20;
  final noteEnd = noteStart + noteLen;
  if (raw.length < noteEnd) return null;
  final note = utf8.decode(raw.sublist(noteStart, noteEnd), allowMalformed: true);

  return SosBeacon(
    msgId: msgId,
    ttl: ttl,
    priority: priority,
    senderId: senderId,
    latMicro: latMicro,
    lonMicro: lonMicro,
    note: note,
  );
}

/// Split a payload into BLE-advertisement-sized frames.
///
/// Each frame: msgId(4 BE) total(1) index(1) chunk(..). `mtu` is the max bytes
/// per advertisement service-data; chunk size is `mtu - _frameHeader`.
List<Uint8List> fragmentBeacon(int msgId, Uint8List payload, int mtu) {
  final chunkSize = (mtu - _frameHeader) < 1 ? 1 : (mtu - _frameHeader);

  final List<Uint8List> chunks = [];
  if (payload.isEmpty) {
    chunks.add(Uint8List(0));
  } else {
    for (var i = 0; i < payload.length; i += chunkSize) {
      final end = (i + chunkSize) > payload.length ? payload.length : i + chunkSize;
      chunks.add(Uint8List.fromList(payload.sublist(i, end)));
    }
  }

  final total = chunks.length > 255 ? 255 : chunks.length;
  final frames = <Uint8List>[];
  for (var idx = 0; idx < total; idx++) {
    final data = chunks[idx];
    final frame = BytesBuilder();
    frame.add(_u32be(msgId));
    frame.addByte(total);
    frame.addByte(idx);
    frame.add(data);
    frames.add(frame.toBytes());
  }
  return frames;
}

/// Convenience: encode a beacon and fragment it ready to advertise.
List<Uint8List> sosMakeFrames(SosBeacon b, int mtu) =>
    fragmentBeacon(b.msgId, encodeSos(b), mtu);

class _Partial {
  final int total;
  final Map<int, Uint8List> chunks = {};
  int lastTick;
  _Partial(this.total, this.lastTick);
}

/// Reassembles advertisement frames into full payloads, with dedup.
///
/// `tick` is a caller-supplied monotonic counter (e.g. millis) used only for
/// relative ordering during pruning.
class BeaconReassembler {
  final Map<int, _Partial> _partials = {};
  final Set<int> _delivered = {};
  final List<int> _deliveredOrder = [];
  final int _maxDelivered;

  BeaconReassembler({int maxDelivered = 512}) : _maxDelivered = maxDelivered;

  bool alreadyDelivered(int msgId) => _delivered.contains(msgId);

  /// Feed one received frame. Returns the full payload exactly once, when the
  /// final missing fragment of a not-yet-delivered message arrives.
  Uint8List? pushFrame(Uint8List frame, int tick) {
    if (frame.length < _frameHeader) return null;
    final msgId = _readU32be(frame, 0);
    final total = frame[4];
    final index = frame[5];
    if (total == 0 || index >= total) return null;
    final chunk = Uint8List.fromList(frame.sublist(_frameHeader));

    if (_delivered.contains(msgId)) return null; // duplicate of emitted SOS

    final entry = _partials.putIfAbsent(msgId, () => _Partial(total, tick));
    if (entry.total != total) return null; // conflicting total
    entry.lastTick = tick;
    entry.chunks[index] = chunk;

    if (entry.chunks.length != entry.total) return null; // still waiting

    final out = BytesBuilder();
    for (var i = 0; i < entry.total; i++) {
      final c = entry.chunks[i];
      if (c == null) return null; // defensive; should not happen
      out.add(c);
    }
    _partials.remove(msgId);
    _markDelivered(msgId);
    return out.toBytes();
  }

  void _markDelivered(int msgId) {
    if (_delivered.add(msgId)) {
      _deliveredOrder.add(msgId);
      while (_deliveredOrder.length > _maxDelivered) {
        final old = _deliveredOrder.removeAt(0);
        _delivered.remove(old);
      }
    }
  }

  /// Drop partial messages older than `maxAge` ticks. Call periodically.
  void prune(int nowTick, int maxAge) {
    _partials.removeWhere((_, p) => (nowTick - p.lastTick) > maxAge);
  }
}

// ── byte helpers (big-endian, two's complement for i32) ──────────────

Uint8List _u32be(int v) {
  final b = ByteData(4)..setUint32(0, v & 0xFFFFFFFF, Endian.big);
  return b.buffer.asUint8List();
}

Uint8List _i32be(int v) {
  final b = ByteData(4)..setInt32(0, v, Endian.big);
  return b.buffer.asUint8List();
}

int _readU32be(Uint8List d, int off) =>
    ByteData.sublistView(d, off, off + 4).getUint32(0, Endian.big);

int _readI32be(Uint8List d, int off) =>
    ByteData.sublistView(d, off, off + 4).getInt32(0, Endian.big);

Uint8List _sender4(Uint8List id) {
  final out = Uint8List(4);
  for (var i = 0; i < 4 && i < id.length; i++) {
    out[i] = id[i];
  }
  return out;
}
