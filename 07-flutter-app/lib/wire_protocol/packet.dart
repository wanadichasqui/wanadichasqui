import 'dart:typed_data';
import 'package:collection/collection.dart';

import 'message_type.dart';

class PacketHeader {
  static final Uint8List magic = Uint8List.fromList([0x57, 0x4E, 0x41, 0x44]);

  final int version;
  final MessageType msgType;
  final int payloadLength;

  const PacketHeader({
    required this.version,
    required this.msgType,
    required this.payloadLength,
  });

  Uint8List encode() {
    final builder = BytesBuilder();

    builder.add(magic);

    builder.addByte(version);

    builder.addByte(msgType.value);

    final len = ByteData(4);

    len.setUint32(
      0,
      payloadLength,
      Endian.big,
    );

    builder.add(
      len.buffer.asUint8List(),
    );

    return builder.takeBytes();
  }

  static PacketHeader decode(Uint8List bytes) {
    if (bytes.length < 10) {
      throw Exception("Invalid header");
    }

    if (!const ListEquality().equals(
      bytes.sublist(0, 4),
      magic,
    )) {
      throw Exception("Invalid magic");
    }

    final version = bytes[4];

    final msgType = MessageType.fromByte(
      bytes[5],
    );

    final payloadLength = ByteData.sublistView(
      bytes,
      6,
      10,
    ).getUint32(
      0,
      Endian.big,
    );

    return PacketHeader(
      version: version,
      msgType: msgType,
      payloadLength: payloadLength,
    );
  }
}

class Packet {
  final PacketHeader header;
  final Uint8List payload;
  Uint8List mac;

  Packet({
    required this.header,
    required this.payload,
    Uint8List? mac,
  }) : mac = mac ?? Uint8List(32);

  factory Packet.create({
    required MessageType messageType,
    required Uint8List payload,
  }) {
    return Packet(
      header: PacketHeader(
        version: 1,
        msgType: messageType,
        payloadLength: payload.length,
      ),
      payload: payload,
    );
  }

  Uint8List encode() {
    final builder = BytesBuilder();

    builder.add(header.encode());
    builder.add(payload);
    builder.add(mac);

    return builder.takeBytes();
  }
}
