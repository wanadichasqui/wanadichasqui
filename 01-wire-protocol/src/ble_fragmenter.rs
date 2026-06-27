pub struct BleSubChunk {
    pub total_sub_chunks: u8,
    pub sub_chunk_index: u8,
    pub payload: Vec<u8>,
}

/// Divide un paquete binario estándar de WNAD en partes aptas para el MTU de BLE (≈500 bytes)
pub fn fragment_wnad_for_ble(raw_wnad: &[u8]) -> Vec<Vec<u8>> {
    let max_ble_payload = 500; // bytes de carga útil segura para BLE
    let chunks: Vec<&[u8]> = raw_wnad.chunks(max_ble_payload).collect();
    let total = chunks.len() as u8;
    chunks
        .into_iter()
        .enumerate()
        .map(|(idx, data)| {
            let mut packet = Vec::with_capacity(2 + data.len());
            packet.push(total); // byte 0: número total de sub‑chunks
            packet.push(idx as u8); // byte 1: índice de este sub‑chunk
            packet.extend_from_slice(data);
            packet
        })
        .collect()
}
