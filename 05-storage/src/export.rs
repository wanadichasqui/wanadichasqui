//! Exportación de la base de datos cifrada (identidad portable).
//!
//! El proceso consiste en:
//!   1. Abrir la base de datos con la contraseña maestra.
//!   2. Extraer todas las filas de `identidades` y `contactos`.
//!   3. Serializar a JSON estructurado.
//!   4. Cifrar el JSON con una clave derivada de una *passphrase* de exportación
//!      (puede ser la misma que la contraseña maestra o una distinta).
//!   5. Guardar el blob resultante en `export_path`.
//!
//! Se utiliza `chacha20poly1305::XChaCha20Poly1305` (nonce de 24 bytes) para
//! garantizar confidencialidad e integridad.

use std::fs::File;
use std::io::Write;
use std::path::Path;
use anyhow::Result;
use serde::{Serialize, Deserialize};
use serde_json::json;
use chacha20poly1305::{XChaCha20Poly1305, aead::{Aead, KeyInit, generic_array::GenericArray}};
use crate::vault::{open_encrypted_db, derive_key, Identity};

#[derive(Debug, Serialize, Deserialize)]
struct ExportPayload {
    identidades: Vec<Identity>,
    contactos: Vec<serde_json::Value>, // guardamos los contactos como JSON genérico
}

/// Exporta la base de datos a un archivo cifrado.
///
/// * `db_path` – ruta del archivo SQLite cifrado.
/// * `master_pwd` – contraseña que protege la base de datos (para abrirla).
/// * `export_pwd` – contraseña para proteger el archivo exportado.
/// * `export_path` – destino del archivo exportado.

pub fn export_storage<P: AsRef<Path>>(
    db_path: P,
    master_pwd: &str,
    export_pwd: &str,
    export_path: P,
) -> Result<()> {
    // 1. Abrir DB
    let conn = open_encrypted_db(&db_path, master_pwd)?;
    // 2. Extraer identidades
    let mut stmt = conn.prepare("SELECT id, clave_pub, alias_local, metadata, claves_efem FROM identidades")?;
    let ident_iter = stmt.query_map([], |row| {
        let metadata_json: String = row.get(3)?;
        let efem_json: String = row.get(4)?;
        Ok(Identity {
            id: row.get(0)?,
            clave_pub: row.get(1)?,
            alias_local: row.get(2)?,
            metadata: serde_json::from_str(&metadata_json).unwrap_or(json!({})),
            claves_efem: serde_json::from_str(&efem_json).unwrap_or_default(),
        })
    })?;
    let mut identidades = Vec::new();
    for i in ident_iter { identidades.push(i?); }

    // 3. Extraer contactos (guardamos como JSON bruto)
    let mut contacts = Vec::new();
    let mut stmt_c = conn.prepare("SELECT id, clave_pub_contacto, alias_local, clave_sesion, huella_verif FROM contactos")?;
    let contacts_iter = stmt_c.query_map([], |row| {
        let obj = json!({
            "id": row.get::<_, i64>(0)?,
            "clave_pub_contacto": row.get::<_, String>(1)?,
            "alias_local": row.get::<_, Option<String>>(2)?,
            "clave_sesion": row.get::<_, Option<String>>(3)?,
            "huella_verif": row.get::<_, Option<String>>(4)?,
        });
        Ok(obj)
    })?;
    for c in contacts_iter { contacts.push(c?); }

    let payload = ExportPayload { identidades, contactos: contacts };
    let json_bytes = serde_json::to_vec(&payload)?;

    // 4. Derivar clave de exportación (32 bytes) usando Argon2 con un salt aleatorio de 16 bytes.
    let mut salt = [0u8; 16];
    getrandom::getrandom(&mut salt).map_err(|e| anyhow::anyhow!(e))?;
    let key = derive_key(export_pwd, &salt);
    let cipher = XChaCha20Poly1305::new(GenericArray::from_slice(&key));
    // nonce aleatorio de 24 bytes
    let mut nonce = [0u8; 24];
    getrandom::getrandom(&mut nonce).map_err(|e| anyhow::anyhow!(e))?;
    let ciphertext = cipher.encrypt(GenericArray::from_slice(&nonce), json_bytes.as_ref())
        .map_err(|e| anyhow::anyhow!(e))?;

    // 5. Guardar: [salt(16)] + [nonce(24)] + [ciphertext]
    let mut out = File::create(export_path)?;
    out.write_all(&salt)?;
    out.write_all(&nonce)?;
    out.write_all(&ciphertext)?;
    Ok(())
}
