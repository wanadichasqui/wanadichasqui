use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use bytes::Bytes;
use wire_protocol::{Packet, MessageType, FileChunk};
use dht_simple::blob_store::BlobStore;
use std::sync::{Arc, Mutex};

use std::collections::HashMap;
use axum::extract::ws::Message;

use std::sync::atomic::AtomicU64;

/// Shared state for the mix‑node.
#[derive(Clone)]
pub struct NodeState {
    pub blob_store: Arc<Mutex<BlobStore>>, // almacenamiento temporal de blobs
    pub clients: Arc<Mutex<HashMap<String, tokio::sync::mpsc::UnboundedSender<Message>>>>,
    pub groups: Arc<Mutex<HashMap<String, Vec<String>>>>,
    pub messages_processed: Arc<AtomicU64>,
    pub bytes_processed: Arc<AtomicU64>,
}

impl NodeState {
    pub fn new() -> Self {
        Self {
            blob_store: Arc::new(Mutex::new(BlobStore::new())),
            clients: Arc::new(Mutex::new(HashMap::new())),
            groups: Arc::new(Mutex::new(HashMap::new())),
            messages_processed: Arc::new(AtomicU64::new(0)),
            bytes_processed: Arc::new(AtomicU64::new(0)),
        }
    }

    pub fn new_persistent<P: AsRef<std::path::Path>>(path: P) -> Self {
        Self {
            blob_store: Arc::new(Mutex::new(BlobStore::new_persistent(path))),
            clients: Arc::new(Mutex::new(HashMap::new())),
            groups: Arc::new(Mutex::new(HashMap::new())),
            messages_processed: Arc::new(AtomicU64::new(0)),
            bytes_processed: Arc::new(AtomicU64::new(0)),
        }
    }
}

/// Handler que recibe un paquete binario (raw bytes).
/// Espera `MessageType::FileChunk` y lo guarda en el `BlobStore`.
pub async fn handle_file_chunk(
    State(state): State<NodeState>,
    body: Bytes,
) -> impl IntoResponse {
    // Decodificamos el paquete completo.
    let pkt = match Packet::decode(&body) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("packet decode error: {}", e);
            return (StatusCode::BAD_REQUEST, "bad packet");
        }
    };
    if pkt.header.msg_type != MessageType::FileChunk {
        return (StatusCode::BAD_REQUEST, "wrong type");
    }
    // Decodificamos el payload como FileChunk.
    let chunk = match FileChunk::decode(&pkt.payload) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("file chunk decode error: {}", e);
            return (StatusCode::BAD_REQUEST, "bad chunk");
        }
    };
    // Guardamos el data del chunk en el BlobStore usando el file_id como clave.
    // Para la prueba simple, concatenamos chunks en memoria.
    // En producción se usaría una estructura más sofisticada.
    {
        let mut store = state.blob_store.lock().unwrap();
        // Si el blob ya existe, simplemente añadimos al vector existente.
        // Usamos `entry` manual porque `BlobStore` solo tiene `put` que genera el hash.
        // Aquí almacenamos cada chunk como parte del archivo completo.
        let mut existing = store.get(&chunk.file_id).unwrap_or_default();
        // Expandir el vector al tamaño necesario.
        let offset = (chunk.chunk_index as usize) * 1024;
        if existing.len() < offset {
            existing.resize(offset, 0);
        }
        // Insertamos datos del chunk.
        if existing.len() < offset + chunk.data.len() {
            existing.resize(offset + chunk.data.len(), 0);
        }
        existing[offset..offset + chunk.data.len()].copy_from_slice(&chunk.data);
        // Sobrescribimos la entrada.
        store.insert(chunk.file_id, existing);
    }

    // Increment metrics counters
    state.messages_processed.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    state.bytes_processed.fetch_add(body.len() as u64, std::sync::atomic::Ordering::Relaxed);

    (StatusCode::OK, "ok")
}
