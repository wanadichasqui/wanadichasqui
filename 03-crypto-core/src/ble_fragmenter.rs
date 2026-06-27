//! Fragmentador táctico de paquetes WNAD para BLE (MTU ≤ 502 bytes).
pub fn fragment_wnad_for_ble(raw: &[u8]) -> Vec<Vec<u8>> {
    let max_chunk = 500;
    let total = (raw.len() + max_chunk - 1) / max_chunk;
    raw.chunks(max_chunk)
        .enumerate()
        .map(|(i, chunk)| {
            let mut out = Vec::with_capacity(2 + chunk.len());
            out.push(total as u8);
            out.push(i as u8);
            out.extend_from_slice(chunk);
            out
        })
        .collect()
}
