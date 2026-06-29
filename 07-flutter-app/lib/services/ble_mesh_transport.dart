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

/// Connectionless BLE mesh transport for emergency SOS beacons.
///
/// TX: SOS beacons are fragmented (see [ble_beacon_codec]) and each frame is
/// advertised as BLE manufacturer-data, rotating round-robin over a timer
/// (only one advertisement can be active at a time).
///
/// RX: the device scan surfaces neighbours' manufacturer-data; matching frames
/// are reassembled, decoded, emitted on [onSos], and — if their TTL allows —
/// re-broadcast (relayed) so beacons hop phone-to-phone. That relay loop is the
/// mesh. Dedup (by msgId) in the reassembler stops relay storms.
///
/// No internet, no cell tower, no server. Works in a blackout.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_beacon_codec.dart';

class BleMeshTransport {
  /// Reserved "for testing" Bluetooth SIG company id. Marks our beacons so we
  /// ignore unrelated manufacturer advertisements.
  static const int companyId = 0xFFFF;

  /// Bytes per advertised frame. Keeps the AD packet within the ~31-byte
  /// legacy budget (companyId 2B + frame + AD overhead).
  static const int mtu = 20;

  /// How long each frame is advertised before rotating to the next.
  static const Duration advertiseSlot = Duration(milliseconds: 700);

  /// Default hop budget for a freshly created SOS.
  static const int defaultTtl = 6;

  /// Cap on queued frames so relays can't grow unbounded.
  static const int _maxTxFrames = 90;

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final BeaconReassembler _reassembler = BeaconReassembler();

  final StreamController<SosBeacon> _sosController =
      StreamController<SosBeacon>.broadcast();

  /// Emits every distinct SOS beacon received over the mesh (deduped).
  Stream<SosBeacon> get onSos => _sosController.stream;

  final List<Uint8List> _txQueue = [];
  int _txIndex = 0;
  int _tick = 0;
  bool _running = false;

  Timer? _txTimer;
  StreamSubscription<DiscoveredDevice>? _scanSub;

  bool get isRunning => _running;

  /// Whether this device can advertise (act as a relay/originator). Scanning
  /// still works on devices that cannot advertise — they receive and display.
  Future<bool> canAdvertise() async {
    try {
      return await _peripheral.isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Begin scanning and the advertise rotation. Caller must have already
  /// granted BLE + location permissions.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    // ScanMode.balanced: recibe SOS de forma fiable consumiendo mucha menos
    // batería que lowLatency. La batería es supervivencia en un apagón.
    _scanSub = _ble
        .scanForDevices(withServices: const [], scanMode: ScanMode.balanced)
        .listen(_onDevice, onError: (Object e) {
      debugPrint('BleMeshTransport scan error: $e');
    });

    _txTimer = Timer.periodic(advertiseSlot, (_) => _onSlot());
  }

  Future<void> stop() async {
    _running = false;
    _txTimer?.cancel();
    _txTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _peripheral.stop();
    } catch (_) {}
  }

  /// Queue an SOS beacon for continuous mesh broadcast.
  void broadcastSos(SosBeacon beacon) {
    _enqueueFrames(sosMakeFrames(beacon, mtu));
  }

  // ── RX ────────────────────────────────────────────────────────────

  void _onDevice(DiscoveredDevice device) {
    final md = device.manufacturerData;
    // Android prefixes manufacturer data with the 2-byte company id (LE).
    if (md.length < 2 + _frameMinLen) return;
    final cid = md[0] | (md[1] << 8);
    if (cid != companyId) return;

    final frame = Uint8List.fromList(md.sublist(2));
    _tick++;
    final payload = _reassembler.pushFrame(frame, _tick);
    if (payload == null) return;

    final sos = decodeSos(payload);
    if (sos == null) return;

    _sosController.add(sos);

    // Relay onward if still within hop budget.
    final relayed = sos.relayed();
    if (relayed != null) {
      _enqueueFrames(sosMakeFrames(relayed, mtu));
    }
  }

  // Minimum useful frame length: header (6) + at least 1 payload byte.
  static const int _frameMinLen = 7;

  // ── TX rotation ───────────────────────────────────────────────────

  void _enqueueFrames(List<Uint8List> frames) {
    _txQueue.addAll(frames);
    // Drop oldest frames if we exceed the cap (keeps the freshest beacons).
    while (_txQueue.length > _maxTxFrames) {
      _txQueue.removeAt(0);
      if (_txIndex > 0) _txIndex--;
    }
  }

  Future<void> _onSlot() async {
    // Opportunistic prune of stale partial reassemblies.
    if (_tick % 20 == 0) {
      _reassembler.prune(_tick, 200);
    }
    if (_txQueue.isEmpty) return;

    if (_txIndex >= _txQueue.length) _txIndex = 0;
    final frame = _txQueue[_txIndex];
    _txIndex++;

    try {
      // Restart advertising with the next frame's manufacturer data.
      await _peripheral.stop();
      await _peripheral.start(
        advertiseData: AdvertiseData(
          manufacturerId: companyId,
          manufacturerData: frame,
          includeDeviceName: false,
        ),
      );
    } catch (e) {
      debugPrint('BleMeshTransport advertise error: $e');
    }
  }

  void dispose() {
    stop();
    _sosController.close();
  }
}
