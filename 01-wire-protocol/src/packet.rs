use bytes::{Buf, BufMut, Bytes, BytesMut};
use std::io::Read;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Tipos de mensaje dentro del protocolo binario.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum MessageType {
    Text = 0x01,
    FileChunk = 0x02,
    LinkMeta = 0x03,
    GroupCommit = 0x10,
    GroupProposal = 0x11,
    GroupMessage = 0x12,
    ZKProof = 0x20,
    CallSignal = 0x30,
    Dummy = 0xFF,
}

/// Cabecera fija del paquete.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Header {
    pub magic: [u8; 4],   // "WNAD"
    pub version: u8,
    pub msg_type: MessageType,
    pub payload_len: u32, // big‑endian
}

/// Representa un paquete completo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Packet {
    pub header: Header,
    pub payload: Bytes,   // payload crudo (texto, chunk, metadata)
    pub mac: [u8; 32],    // placeholder MAC (se rellenará en capa crypto)
}

impl Packet {
    const MAGIC: [u8; 4] = *b"WNAD";

    /// Crea un paquete nuevo con el tipo y payload indicados.
    pub fn new(msg_type: MessageType, payload: impl Into<Bytes>) -> Self {
        let payload = payload.into();
        let payload_len = payload.len() as u32;

        Packet {
            header: Header {
                magic: Self::MAGIC,
                version: 1,
                msg_type,
                payload_len,
            },
            payload,
            mac: [0u8; 32], // el ratchet‑layer lo rellenará
        }
    }

    /// Calcula el MAC real del paquete (cabecera + payload) usando HMAC-SHA256 con una clave dada.
    pub fn compute_mac(&self, key: &[u8; 32]) -> [u8; 32] {
        use hmac::{Hmac, Mac};
        use sha2::Sha256;
        type HmacSha256 = Hmac<Sha256>;

        let mut mac = HmacSha256::new_from_slice(key).expect("HMAC can take key of any size");
        mac.update(&self.header.magic);
        mac.update(&[self.header.version]);
        mac.update(&[self.header.msg_type as u8]);
        mac.update(&self.header.payload_len.to_be_bytes());
        mac.update(&self.payload);

        let result = mac.finalize();
        let mut out = [0u8; 32];
        out.copy_from_slice(&result.into_bytes());
        out
    }

    /// Rellena el campo `mac` del paquete calculándolo con la clave dada.
    pub fn sign_with_key(&mut self, key: &[u8; 32]) {
        self.mac = self.compute_mac(key);
    }

    /// Verifica si el MAC del paquete coincide con el calculado usando la clave dada.
    pub fn verify_with_key(&self, key: &[u8; 32]) -> bool {
        use subtle::ConstantTimeEq;
        let expected = self.compute_mac(key);
        self.mac.ct_eq(&expected).unwrap_u8() == 1
    }

    /// Serializa a `bytes::Bytes`.
    pub fn encode(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(42 + self.payload.len());
        buf.put_slice(&self.header.magic);
        buf.put_u8(self.header.version);
        buf.put_u8(self.header.msg_type as u8);
        buf.put_u32(self.header.payload_len);
        buf.put_slice(&self.payload);
        buf.put_slice(&self.mac);
        buf.freeze()
    }

    /// Deserializa desde un slice; valida cabecera y tamaños.
    pub fn decode(mut src: &[u8]) -> Result<Self, &'static str> {
        if src.len() < 42 {
            return Err("buffer too short for header");
        }
        let mut magic = [0u8; 4];
        src.read_exact(&mut magic).map_err(|_| "read magic")?;
        if magic != Self::MAGIC {
            return Err("invalid magic");
        }
        let version = src.get_u8();
        let msg_type = src.get_u8();
        let payload_len = src.get_u32();
        let msg_type = match msg_type {
            0x01 => MessageType::Text,
            0x02 => MessageType::FileChunk,
            0x03 => MessageType::LinkMeta,
            0x10 => MessageType::GroupCommit,
            0x11 => MessageType::GroupProposal,
            0x12 => MessageType::GroupMessage,
            0x20 => MessageType::ZKProof,
            0x30 => MessageType::CallSignal,
            0xFF => MessageType::Dummy,
            _ => return Err("unknown message type"),
        };
        if src.len() < payload_len as usize + 32 {
            return Err("payload length mismatch");
        }
        let payload = Bytes::copy_from_slice(&src[..payload_len as usize]);
        src = &src[payload_len as usize..];
        let mut mac = [0u8; 32];
        src.read_exact(&mut mac).map_err(|_| "read mac")?;
        Ok(Packet {
            header: Header {
                magic,
                version,
                msg_type,
                payload_len,
            },
            payload,
            mac,
        })
    }
}

// ---------------------------------------------------------------------------
//   Chunk de archivo (documentos)
// ---------------------------------------------------------------------------
/// Payload para `MessageType::FileChunk`.
///
/// Layout binario (little‑endian para índices y tamaños):
/// ```text
/// [file_id: 32 bytes]          // SHA‑256 del archivo completo
/// [chunk_index: u32]           // índice empezando en 0
/// [total_chunks: u32]          // número total de chunks
/// [data_len: u16]              // longitud del bloque de datos (<= 1024)
/// [data: variable]             // bytes del chunk
/// ```
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileChunk {
    pub file_id: [u8; 32],
    pub chunk_index: u32,
    pub total_chunks: u32,
    pub data: Bytes, // ≤ 1024 bytes (en práctica)
}

impl FileChunk {
    /// Serializa el chunk a `Bytes` listo para ir dentro del `Packet` payload.
    pub fn encode(&self) -> Bytes {
        let mut buf = BytesMut::with_capacity(32 + 4 + 4 + 2 + self.data.len());
        buf.put_slice(&self.file_id);
        buf.put_u32_le(self.chunk_index);
        buf.put_u32_le(self.total_chunks);
        buf.put_u16_le(self.data.len() as u16);
        buf.put_slice(&self.data);
        buf.freeze()
    }

    /// Deserializa un `FileChunk` desde un slice.
    pub fn decode(mut src: &[u8]) -> Result<Self, &'static str> {
        if src.len() < 32 + 4 + 4 + 2 {
            return Err("buffer too short for FileChunk header");
        }
        let mut file_id = [0u8; 32];
        src.read_exact(&mut file_id).map_err(|_| "read file_id")?;
        let chunk_index = src.get_u32_le();
        let total_chunks = src.get_u32_le();
        let data_len = src.get_u16_le() as usize;
        if src.len() < data_len {
            return Err("buffer too short for chunk data");
        }
        let data = Bytes::copy_from_slice(&src[..data_len]);
        Ok(FileChunk {
            file_id,
            chunk_index,
            total_chunks,
            data,
        })
    }
}

// Helper para crear el file_id (SHA‑256) a partir de los bytes completos.
pub fn compute_file_id(full_data: &[u8]) -> [u8; 32] {
    let hash = Sha256::digest(full_data);
    let mut out = [0u8; 32];
    out.copy_from_slice(&hash);
    out
}
