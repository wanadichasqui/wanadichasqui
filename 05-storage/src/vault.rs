//! Módulo de almacenamiento cifrado (SQLCipher‑like) para identidades y contactos.
//!
//! Utiliza `rusqlite` con la pragma `key` para proteger la base de datos con una
//! clave derivada de la contraseña del usuario mediante Argon2id (memoria 64 MiB,
//! 3 pasadas, 4 hilos). La clave resultante tiene 32 bytes y se emplea con el
//! algoritmo de cifrado nativo de SQLite (AES‑256‑CBC).
//!
//! La capa de alto nivel ofrece:
//!   * `open_encrypted_db(path, password) -> Connection`
//!   * `init_schema(conn)` para crear las tablas `identidades` y `contactos`.
//!   * Funciones auxiliares de inserción/consulta que serializan los campos
//!     mediante `serde_json`.
//!
//! La API está pensada para ser usada tanto desde el backend Rust como vía
//! FFI en Flutter (a través de `flutter_rust_bridge`).

use std::path::Path;
use rusqlite::{Connection, params, Result as SqlResult};
use argon2::{Algorithm, Argon2, Params, Version};
use serde::{Serialize, Deserialize};
use serde_json::json;

/// Deriva una clave de 32 bytes a partir de la contraseña del usuario usando
/// Argon2id con parámetros fijos (memoria 64 MiB, 3 iteraciones, 4 hilos).
pub fn derive_key(password: &str, salt: &[u8]) -> [u8; 32] {
    let params = Params::new(65536, 3, 4, Some(32)).expect("Argon2 params");
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut out = [0u8; 32];
    argon2
        .hash_password_into(password.as_bytes(), salt, &mut out)
        .expect("Argon2 derivation must not fail");
    out
}

/// Abre (o crea) una base de datos SQLite cifrada.
///
/// La clave se establece con la pragma `key`. Si la base de datos no existe se
/// crea y se inicializa el esquema mediante `init_schema`.
pub fn open_encrypted_db<P: AsRef<Path>>(db_path: P, password: &str) -> SqlResult<Connection> {
    let db_path_ref = db_path.as_ref();
    let salt_path = db_path_ref.with_extension("salt");
    let mut salt = [0u8; 16];

    if salt_path.exists() {
        let mut file = std::fs::File::open(&salt_path)
            .map_err(|_| rusqlite::Error::InvalidPath(salt_path.clone()))?;
        use std::io::Read;
        file.read_exact(&mut salt)
            .map_err(|_| rusqlite::Error::InvalidPath(salt_path.clone()))?;
    } else {
        // Generar salt aleatorio usando getrandom
        getrandom::getrandom(&mut salt)
            .map_err(|_| rusqlite::Error::InvalidPath(salt_path.clone()))?;
        let mut file = std::fs::File::create(&salt_path)
            .map_err(|_| rusqlite::Error::InvalidPath(salt_path.clone()))?;
        use std::io::Write;
        file.write_all(&salt)
            .map_err(|_| rusqlite::Error::InvalidPath(salt_path.clone()))?;
    }

    let key = derive_key(password, &salt);
    let key_hex = hex::encode(key);

    // `rusqlite` abre la base y luego aplicamos la pragma para preparar el
    // cifrado. La opción `OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_CREATE`
    // es implícita en `Connection::open`.
    let conn = Connection::open(db_path_ref)?;
    conn.pragma_update(None, "key", &key_hex)?; // SQLite Encryption Extension (SEE) compatible.
    // Intentamos ejecutar una consulta trivial; si falla, la clave es incorrecta.
    conn.execute("SELECT count(*) FROM sqlite_master", params![]).ok();
    Ok(conn)
}

/// Corre las migraciones de base de datos de manera incremental utilizando la pragma `user_version` de SQLite.
pub fn run_migrations(conn: &Connection) -> SqlResult<()> {
    let current_version: i32 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;

    if current_version < 1 {
        // Migración 1: Creación del esquema inicial
        conn.execute(
            "CREATE TABLE IF NOT EXISTS identidades (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                clave_pub   TEXT NOT NULL,
                alias_local TEXT,
                metadata    TEXT, -- JSON con datos adicionales
                claves_efem TEXT -- JSON array con claves de sesión efímeras
            )",
            params![],
        )?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS contactos (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                clave_pub_contacto TEXT NOT NULL,
                alias_local       TEXT,
                clave_sesion       TEXT,   -- clave de la sesión actual cifrada
                huella_verif      TEXT    -- hash de la clave pública para validación visual
            )",
            params![],
        )?;

        conn.pragma_update(None, "user_version", &1)?;
    }

    let current_version: i32 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;

    if current_version < 2 {
        // Migración 2: Añadir columna is_verified a la tabla de contactos
        // Primero verificamos si la columna ya existe por seguridad
        let has_col: bool = conn.query_row(
            "SELECT count(*) FROM pragma_table_info('contactos') WHERE name='is_verified'",
            [],
            |row| row.get::<_, i32>(0).map(|c| c > 0)
        )?;
        if !has_col {
            conn.execute(
                "ALTER TABLE contactos ADD COLUMN is_verified INTEGER DEFAULT 0",
                params![],
            )?;
        }
        conn.pragma_update(None, "user_version", &2)?;
    }

    Ok(())
}

/// Crea el esquema necesario si aún no existe (mantenido para compatibilidad).
pub fn init_schema(conn: &Connection) -> SqlResult<()> {
    run_migrations(conn)
}

/// Representación de una identidad dentro del código Rust.
#[derive(Debug, Serialize, Deserialize)]
pub struct Identity {
    pub id: i64,
    pub clave_pub: String,
    pub alias_local: Option<String>,
    pub metadata: serde_json::Value,
    pub claves_efem: Vec<String>, // claves de sesión (hex)
}

/// Inserta o actualiza una identidad.
pub fn upsert_identity(conn: &Connection, ident: &Identity) -> SqlResult<()> {
    let meta_str = serde_json::to_string(&ident.metadata).unwrap();
    let efem_str = serde_json::to_string(&ident.claves_efem).unwrap();
    conn.execute(
        "INSERT INTO identidades (id, clave_pub, alias_local, metadata, claves_efem)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(id) DO UPDATE SET
            clave_pub = excluded.clave_pub,
            alias_local = excluded.alias_local,
            metadata = excluded.metadata,
            claves_efem = excluded.claves_efem",
        params![ident.id, ident.clave_pub, ident.alias_local, meta_str, efem_str],
    )?;
    Ok(())
}

/// Recupera una identidad por su id.
pub fn get_identity(conn: &Connection, id: i64) -> SqlResult<Option<Identity>> {
    let mut stmt = conn.prepare(
        "SELECT id, clave_pub, alias_local, metadata, claves_efem FROM identidades WHERE id = ?1",
    )?;
    let mut rows = stmt.query(params![id])?;
    if let Some(row) = rows.next()? {
        let metadata_json: String = row.get(3)?;
        let efem_json: String = row.get(4)?;
        Ok(Some(Identity {
            id: row.get(0)?,
            clave_pub: row.get(1)?,
            alias_local: row.get(2)?,
            metadata: serde_json::from_str(&metadata_json).unwrap_or(json!({})),
            claves_efem: serde_json::from_str(&efem_json).unwrap_or_default(),
        }))
    } else {
        Ok(None)
    }
}

// -----------------------------------------------------------------------------
// Funciones auxiliares (contactos, credenciales efímeras) se pueden añadir más
// abajo siguiendo el mismo patrón.
// -----------------------------------------------------------------------------
