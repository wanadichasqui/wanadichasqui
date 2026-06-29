enum MessageType {
  text(0x01),
  fileChunk(0x02),
  linkMeta(0x03),

  groupCommit(0x10),
  groupProposal(0x11),
  groupMessage(0x12),

  zkProof(0x20),

  callSignal(0x30),

  dummy(0xFF);

  final int value;

  const MessageType(this.value);

  static MessageType fromByte(int value) {
    for (final type in MessageType.values) {
      if (type.value == value) {
        return type;
      }
    }
    throw Exception("Unknown message type: 0x${value.toRadixString(16)}");
  }
}
