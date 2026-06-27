//! Notificaciones locales sin FCM/APNs.
//!
//! Este crate gestiona una tabla SQLite cifrada con notificaciones
//! programadas que la UI Flutter podrá leer y mostrar mediante notificaciones
//! locales del propio dispositivo. La base de datos se almacena usando el
//! mismo mecanismo de cifrado que el crate `storage` (SQLCipher‑like).
//!
//! La tabla `notificaciones` tiene los campos:
//!   * `id` – PK autoincremental.
//!   * `title` – título de la notificación.
//!   * `body` – cuerpo del mensaje.
//!   * `scheduled_at` – timestamp Unix (segundos) en que debe mostrarse.
//!   * `payload` – JSON opcional con datos extra (por ej. ID de conversación).
//!   * `delivered` – flag booleano que indica si ya se disparó.
//!
//! La API pública está en `api.rs` y está expuesta a Flutter mediante
//! `flutter_rust_bridge` (`#[frb]`).

pub mod api;
pub mod models;
