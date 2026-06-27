#[cfg(test)]
mod tests {
    use super::*;
    use crate::{compute_file_id, FileChunk, MessageType, Packet};
    use proptest::prelude::*;
    use bytes::Bytes;

    // Generador de datos aleatorios (≤ 64 KiB) para round‑trip.
    fn arb_file_data() -> impl Strategy<Value = Vec<u8>> {
        // Limitamos a 64 KiB (64 * 1024 bytes) para evitar test lentos en debug.
        prop::collection::vec(any::<u8>(), 0..=64 * 1024)
    }

    proptest! {
        #[test]
        fn packet_roundtrip_file(data in arb_file_data()) {
            // Simulamos dividir el archivo en chunks de 1024 bytes.
            let file_id = compute_file_id(&data);
            let chunks: Vec<FileChunk> = data
                .chunks(1024)
                .enumerate()
                .map(|(i, chunk)| FileChunk {
                    file_id,
                    chunk_index: i as u32,
                    total_chunks: ((data.len() + 1023) / 1024) as u32,
                    data: Bytes::copy_from_slice(chunk),
                })
                .collect();

            // Cada chunk se empaqueta en un Packet y se decodifica.
            for c in &chunks {
                let payload = c.encode();
                let pkt = Packet::new(MessageType::FileChunk, payload.clone());
                let enc = pkt.encode();
                let dec = Packet::decode(&enc).expect("decode packet");
                assert_eq!(dec.header.msg_type, MessageType::FileChunk);
                let decoded_chunk = FileChunk::decode(&dec.payload).expect("decode chunk");
                assert_eq!(decoded_chunk, *c);
            }
        }
    }

    #[test]
    fn test_mac_signing_and_verification() {
        let key = [0x55u8; 32];
        let bad_key = [0x99u8; 32];
        let payload = b"Hello Chasqui MAC test";
        let mut pkt = Packet::new(MessageType::Text, &payload[..]);
        
        // El MAC inicial debe ser todo ceros
        assert_eq!(pkt.mac, [0u8; 32]);
        
        // Firmamos
        pkt.sign_with_key(&key);
        assert_ne!(pkt.mac, [0u8; 32]);
        
        // Verificamos con clave correcta
        assert!(pkt.verify_with_key(&key));
        
        // Verificamos con clave incorrecta
        assert!(!pkt.verify_with_key(&bad_key));

        // Codificamos y decodificamos, y nos aseguramos de que el MAC siga siendo válido
        let enc = pkt.encode();
        let dec = Packet::decode(&enc).expect("decode signed packet");
        assert_eq!(dec.mac, pkt.mac);
        assert!(dec.verify_with_key(&key));
        assert!(!dec.verify_with_key(&bad_key));
    }
}
