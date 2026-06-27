//! Importación de una identidad portable cifrada.
//!
//! El proceso es el inverso de la exportación:
//!   1. Leer el archivo exportado.
//!   2. Separar nonce (24 bytes) y ciphertext.
//!   3. Derivar la clave de exportación con Argon2.
//!   4. Descifrar con XChaCha20Poly1305.
//!   5. Insertar las identidades y contactos en una base de datos SQLite cifrada.

use std::fs::File;
use std::io::Read;
use std::path::Path;
// // use rusqlite::Connection; // not directly used // not needed directly
use serde::{Serialize, Deserialize};
// use serde_json::Value; // not needed
use chacha20poly1305::{XChaCha20Poly1305, aead::{Aead, KeyInit, generic_array::GenericArray}};
use crate::vault::{open_encrypted_db, init_schema, derive_key, upsert_identity, Identity};
use anyhow::{Result, anyhow};

#[derive(Debug, Serialize, Deserialize)]
struct ExportPayload {
    identidades: Vec<Identity>,
    contactos: Vec<serde_json::Value>,
}

/// Importa una base de datos desde un archivo exportado cifrado.
///
/// * `export_path` – archivo exportado previamente con `export_storage`.
/// * `export_pwd` – contraseña usada para cifrar el archivo exportado.
/// * `db_path` – destino de la nueva base de datos SQLite cifrada.
/// * `master_pwd` – contraseña maestra que protegerá la nueva base de datos.
pub fn import_storage<P: AsRef<Path>>(
    export_path: P,
    export_pwd: &str,
    db_path: P,
    master_pwd: &str,
) -> Result<()> {
    // 1. Leer archivo
    let mut file = File::open(export_path)?;
    let mut data = Vec::new();
    file.read_to_end(&mut data)?;
    if data.len() < 16 + 24 {
        return Err(anyhow!("archivo exportado demasiado corto"));
    }

    // 2. Separar salt, nonce y ciphertext
    let (salt_and_nonce, ciphertext) = data.split_at(16 + 24);
    let (salt_bytes, nonce_bytes) = salt_and_nonce.split_at(16);
    let nonce = GenericArray::from_slice(nonce_bytes);
    let key = derive_key(export_pwd, salt_bytes);
    let cipher = XChaCha20Poly1305::new(GenericArray::from_slice(&key));
    let plaintext = cipher.decrypt(nonce, ciphertext)
        .map_err(|e| anyhow!(e))?;

    // 3. Deserializar payload
    let payload: ExportPayload = serde_json::from_slice(&plaintext)?;

    // 4. Abrir DB destino
    let mut conn = open_encrypted_db(db_path, master_pwd)?;
    init_schema(&conn)?;

    // 5. Insertar identidades
    for ident in payload.identidades {
        upsert_identity(&conn, &ident)?;
    }

    // 6. Insertar contactos
    let tx = conn.transaction()?;
    for contact in payload.contactos {
        let id = contact["id"].as_i64().unwrap_or_default();
        let clave_pub_contacto = contact["clave_pub_contacto"].as_str().unwrap_or_default();
        let alias_local = contact["alias_local"].as_str().map(|s| s.to_owned());
        let clave_sesion = contact["clave_sesion"].as_str().map(|s| s.to_owned());
        let huella_verif = contact["huella_verif"].as_str().map(|s| s.to_owned());

        tx.execute(
            "INSERT INTO contactos (id, clave_pub_contacto, alias_local, clave_sesion, huella_verif)
             VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(id) DO UPDATE SET
                clave_pub_contacto = excluded.clave_pub_contacto,
                alias_local = excluded.alias_local,
                clave_sesion = excluded.clave_sesion,
                huella_verif = excluded.huella_verif",
            rusqlite::params![id, clave_pub_contacto, alias_local, clave_sesion, huella_verif],
        )?;
    }
    tx.commit()?;

    Ok(())
}
