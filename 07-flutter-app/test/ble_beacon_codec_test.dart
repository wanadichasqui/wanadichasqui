// Copyright (C) 2026 Juan Carlos Diaz Parisca / Wanadi Tactical
// Part of Wanadi Chasqui — AGPLv3. See <https://www.gnu.org/licenses/>.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanadi_chasqui_app/services/ble_beacon_codec.dart';

SosBeacon sample() => SosBeacon(
      msgId: 0xDEADBEEF,
      ttl: 5,
      priority: kPriorityCritical,
      senderId: Uint8List.fromList([1, 2, 3, 4]),
      latMicro: 10491016, // ~10.491016 (Caracas)
      lonMicro: -66902500, // ~-66.9025
      note: 'Atrapado, 2 personas',
    );

void expectSameBeacon(SosBeacon a, SosBeacon b) {
  expect(a.msgId, b.msgId);
  expect(a.ttl, b.ttl);
  expect(a.priority, b.priority);
  expect(a.senderId, b.senderId);
  expect(a.latMicro, b.latMicro);
  expect(a.lonMicro, b.lonMicro);
  expect(a.note, b.note);
}

void main() {
  test('encode/decode roundtrip', () {
    final b = sample();
    final got = decodeSos(encodeSos(b))!;
    expectSameBeacon(b, got);
    expect(got.hasLocation, isTrue);
  });

  test('decode rejects truncated', () {
    expect(decodeSos(Uint8List(0)), isNull);
    expect(decodeSos(Uint8List.fromList([1, 2, 3])), isNull);
    final raw = encodeSos(sample());
    expect(decodeSos(raw.sublist(0, raw.length - 3)), isNull);
  });

  test('no-location sentinel', () {
    final b = SosBeacon(
      msgId: 1,
      ttl: 3,
      priority: kPriorityHelp,
      senderId: Uint8List.fromList([9, 9, 9, 9]),
      latMicro: -2147483648,
      lonMicro: -2147483648,
      note: 'sin gps',
    );
    final got = decodeSos(encodeSos(b))!;
    expect(got.hasLocation, isFalse);
  });

  test('fragment and reassemble', () {
    final b = sample();
    final payload = encodeSos(b);
    final frames = fragmentBeacon(b.msgId, payload, 20);
    expect(frames.length, greaterThan(1));

    final r = BeaconReassembler();
    Uint8List? result;
    for (var i = 0; i < frames.length; i++) {
      final out = r.pushFrame(frames[i], i);
      if (out != null) result = out;
    }
    expect(result, isNotNull);
    expect(result, equals(payload));
    expectSameBeacon(decodeSos(result!)!, b);
  });

  test('reassemble out of order and with duplicates', () {
    final b = sample();
    final payload = encodeSos(b);
    final frames = fragmentBeacon(b.msgId, payload, 16).reversed.toList();

    final r = BeaconReassembler();
    Uint8List? result;
    for (var round = 0; round < 2; round++) {
      for (var i = 0; i < frames.length; i++) {
        final out = r.pushFrame(frames[i], round * 100 + i);
        if (out != null) result = out;
      }
    }
    expect(result, equals(payload));
    expect(r.alreadyDelivered(b.msgId), isTrue);
    expect(r.pushFrame(frames[0], 999), isNull);
  });

  test('prune drops stale partials', () {
    final b = sample();
    final payload = encodeSos(b);
    final frames = fragmentBeacon(b.msgId, payload, 16);

    final r = BeaconReassembler();
    expect(r.pushFrame(frames[0], 0), isNull);
    r.prune(10000, 1000);
    Uint8List? result;
    for (var i = 0; i < frames.length; i++) {
      final out = r.pushFrame(frames[i], 10001 + i);
      if (out != null) result = out;
    }
    expect(result, equals(payload));
  });

  test('relay decrements and expires', () {
    final b = SosBeacon(
      msgId: 7,
      ttl: 2,
      priority: kPriorityCritical,
      senderId: Uint8List.fromList([0, 0, 0, 0]),
      latMicro: -2147483648,
      lonMicro: -2147483648,
      note: 'x',
    );
    final r1 = b.relayed()!;
    expect(r1.ttl, 1);
    expect(r1.relayed(), isNull); // 1 -> 0, dropped
  });

  test('empty payload makes one frame', () {
    final frames = fragmentBeacon(7, Uint8List(0), 20);
    expect(frames.length, 1);
    final r = BeaconReassembler();
    expect(r.pushFrame(frames[0], 0), equals(Uint8List(0)));
  });
}
