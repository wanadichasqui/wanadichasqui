//! Flutter‑Rust‑Bridge (FRB) API surface for the encrypted storage crate.
//!
//! Sólo se exponen los entry‑points que necesita la UI Flutter para
//! administrar identidades y contactos de forma portátil.
//!
//! Cada función está decorada con `#[frb]` para que `flutter_rust_bridge`
//! genere automáticamente el código Dart que llama a Rust mediante FFI.
//!
//! Nota: las funciones devuelven `Result<T, String>` – los errores se convierten
//! a `String` para una transmisión sencilla a Dart.

use crate::{export_storage, import_storage, upsert_identity, get_identity, Identity, init_schema, open_encrypted_db};
use std::path::PathBuf;
use flutter_rust_bridge::frb;

/// Abre o crea la base de datos cifrada y devuelve la ruta del archivo.
///
/// * `db_path` – Path absoluto al archivo SQLite.
/// * `password` – Contraseña maestra del usuario.
#[frb]
pub fn storage_open(db_path: String, password: String) -> Result<(), String> {
    open_encrypted_db(&PathBuf::from(db_path), &password)
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// Inicializa el esquema (tablas) dentro de una base de datos ya abierta.
#[frb]
pub fn storage_init_schema(db_path: String, password: String) -> Result<(), String> {
    let conn = open_encrypted_db(&PathBuf::from(db_path), &password)
        .map_err(|e| e.to_string())?;
    init_schema(&conn).map_err(|e| e.to_string())
}

/// Inserta o actualiza una identidad.
#[frb]
pub fn storage_upsert_identity(db_path: String, password: String, identity: Identity) -> Result<(), String> {
    let conn = open_encrypted_db(&PathBuf::from(db_path), &password)
        .map_err(|e| e.to_string())?;
    upsert_identity(&conn, &identity).map_err(|e| e.to_string())
}

/// Obtiene una identidad por `id`.
#[frb]
pub fn storage_get_identity(db_path: String, password: String, id: i64) -> Result<Option<Identity>, String> {
    let conn = open_encrypted_db(&PathBuf::from(db_path), &password)
        .map_err(|e| e.to_string())?;
    get_identity(&conn, id).map_err(|e| e.to_string())
}

/// Exporta toda la base de datos a un archivo cifrado.
#[frb]
pub fn storage_export(
    db_path: String,
    master_pwd: String,
    export_pwd: String,
    export_path: String,
) -> Result<(), String> {
    export_storage(
        PathBuf::from(db_path),
        &master_pwd,
        &export_pwd,
        PathBuf::from(export_path),
    )
    .map_err(|e| e.to_string())
}

/// Importa una base de datos desde un archivo exportado.
#[frb]
pub fn storage_import(
    export_path: String,
    export_pwd: String,
    db_path: String,
    master_pwd: String,
) -> Result<(), String> {
    import_storage(
        PathBuf::from(export_path),
        &export_pwd,
        PathBuf::from(db_path),
        &master_pwd,
    )
    .map_err(|e| e.to_string())
}
