import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class FileChunk {
  final Uint8List fileId;
  final int chunkIndex;
  final int totalChunks;
  final Uint8List data;

  FileChunk({
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.data,
  }) {
    if (fileId.length != 32) {
      throw Exception("fileId must be exactly 32 bytes.");
    }

    if (data.length > 1024) {
      throw Exception("Chunk larger than 1024 bytes.");
    }
  }

  Uint8List encode() {
    final builder = BytesBuilder();

    builder.add(fileId);

    final idx = ByteData(4);
    idx.setUint32(0, chunkIndex, Endian.little);
    builder.add(idx.buffer.asUint8List());

    final total = ByteData(4);
    total.setUint32(0, totalChunks, Endian.little);
    builder.add(total.buffer.asUint8List());

    final len = ByteData(2);
    len.setUint16(0, data.length, Endian.little);
    builder.add(len.buffer.asUint8List());

    builder.add(data);

    return builder.takeBytes();
  }

  static FileChunk decode(Uint8List bytes) {
    if (bytes.length < 42) {
      throw Exception("Invalid FileChunk.");
    }

    int offset = 0;

    final fileId = Uint8List.fromList(bytes.sublist(offset, offset + 32));
    offset += 32;

    final idx = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.little);
    offset += 4;

    final total = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.little);
    offset += 4;

    final len = ByteData.sublistView(bytes, offset, offset + 2)
        .getUint16(0, Endian.little);
    offset += 2;

    if (bytes.length < offset + len) {
      throw Exception("Chunk payload truncated.");
    }

    final data = Uint8List.fromList(bytes.sublist(offset, offset + len));

    return FileChunk(
      fileId: fileId,
      chunkIndex: idx,
      totalChunks: total,
      data: data,
    );
  }

  static Uint8List computeFileId(List<int> fullData) {
    final digest = sha256.convert(fullData);

    return Uint8List.fromList(digest.bytes);
  }

  String get fileIdHex {
    return fileId.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
}
