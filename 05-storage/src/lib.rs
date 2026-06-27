//! Almacenamiento cifrado para identidades y contactos.
//!
//! Este crate encapsula la base de datos local de Wanadi Chasqui.
//! La clave de la base de datos se deriva de la contraseña del usuario mediante
//! Argon2id, de modo que el archivo resultante queda cifrado en reposo.
//!
//! Además se provee utilidades de exportación e importación para crear
//! copias de seguridad portátiles protegidas por contraseña.

pub mod vault;
pub mod export;
pub mod import;

pub use vault::{
    derive_key,
    get_identity,
    init_schema,
    open_encrypted_db,
    upsert_identity,
    Identity,
};

pub use export::export_storage;
pub use import::import_storage;

