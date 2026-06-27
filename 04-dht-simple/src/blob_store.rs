//! Almacenamiento de blobs persistente SQLite indexado por SHA‑256.

use rusqlite::{Connection, params};
use sha2::{Digest, Sha256};
use std::path::Path;

/// Almacén de blobs persistente en SQLite con clave SHA‑256.
pub struct BlobStore {
    conn: Connection,
}

impl std::fmt::Debug for BlobStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BlobStore").finish()
    }
}

impl Default for BlobStore {
    fn default() -> Self {
        Self::new()
    }
}

impl BlobStore {
    /// Crea un `BlobStore` en memoria por defecto (útil para pruebas).
    pub fn new() -> Self {
        let conn = Connection::open_in_memory().expect("failed to open in-memory database");
        Self::init_db(&conn);
        Self { conn }
    }

    /// Crea un `BlobStore` persistente en disco en la ruta indicada.
    pub fn new_persistent<P: AsRef<Path>>(path: P) -> Self {
        let conn = Connection::open(path).expect("failed to open persistent database");
        Self::init_db(&conn);
        Self { conn }
    }

    fn init_db(conn: &Connection) {
        conn.execute(
            "CREATE TABLE IF NOT EXISTS blobs (
                file_id BLOB PRIMARY KEY,
                data BLOB NOT NULL
            )",
            params![],
        ).expect("failed to create blobs table");
    }

    /// Almacena un blob y devuelve su clave (SHA‑256 del contenido).
    pub fn put(&mut self, data: Vec<u8>) -> [u8; 32] {
        let hash = Sha256::digest(&data);
        let mut key = [0u8; 32];
        key.copy_from_slice(&hash);
        self.insert(key, data);
        key
    }

    /// Inserta o reemplaza un blob con una clave explícita.
    pub fn insert(&mut self, key: [u8; 32], data: Vec<u8>) {
        self.conn.execute(
            "INSERT OR REPLACE INTO blobs (file_id, data) VALUES (?1, ?2)",
            params![key.to_vec(), data],
        ).expect("failed to insert blob");
    }

    /// Recupera un blob por su clave.
    pub fn get(&self, key: &[u8; 32]) -> Option<Vec<u8>> {
        let mut stmt = self.conn.prepare("SELECT data FROM blobs WHERE file_id = ?1").ok()?;
        let mut rows = stmt.query(params![key.to_vec()]).ok()?;
        if let Some(row) = rows.next().ok()? {
            let data: Vec<u8> = row.get(0).ok()?;
            Some(data)
        } else {
            None
        }
    }

    /// Elimina un blob. Devuelve `true` si existía.
    pub fn remove(&mut self, key: &[u8; 32]) -> bool {
        let rows_affected = self.conn.execute(
            "DELETE FROM blobs WHERE file_id = ?1",
            params![key.to_vec()],
        ).unwrap_or(0);
        rows_affected > 0
    }

    /// Número de blobs almacenados.
    pub fn len(&self) -> usize {
        self.conn.query_row(
            "SELECT count(*) FROM blobs",
            params![],
            |row| row.get(0),
        ).unwrap_or(0)
    }

    /// `true` si no hay blobs.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_and_get_roundtrip() {
        let mut store = BlobStore::new();
        let data = b"hola chasqui".to_vec();
        let key = store.put(data.clone());
        assert_eq!(store.get(&key).unwrap(), data);
    }

    #[test]
    fn get_missing_returns_none() {
        let store = BlobStore::new();
        let missing = [0xFFu8; 32];
        assert!(store.get(&missing).is_none());
    }

    #[test]
    fn remove_existing() {
        let mut store = BlobStore::new();
        let key = store.put(b"temporal".to_vec());
        assert!(store.remove(&key));
        assert!(store.get(&key).is_none());
    }

    #[test]
    fn default_is_empty() {
        let store = BlobStore::default();
        assert!(store.is_empty());
        assert_eq!(store.len(), 0);
    }

    #[test]
    fn direct_storage_insert() {
        let mut store = BlobStore::new();
        let file_id = [0xAAu8; 32];
        let data = vec![1, 2, 3, 4];
        store.insert(file_id, data.clone());
        assert_eq!(store.get(&file_id).unwrap(), data);
    }

    #[test]
    fn test_persistence() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("test_blobs.db");

        let file_id = [0xBBu8; 32];
        let data = vec![9, 8, 7, 6];

        // Guardar en la base de datos persistente
        {
            let mut store = BlobStore::new_persistent(&db_path);
            store.insert(file_id, data.clone());
            assert_eq!(store.get(&file_id).unwrap(), data);
        }

        // Volver a abrir y verificar que el dato sobrevive
        {
            let store = BlobStore::new_persistent(&db_path);
            assert_eq!(store.get(&file_id).unwrap(), data);
        }
    }
}
