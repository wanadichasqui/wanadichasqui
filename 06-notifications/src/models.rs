use serde::{Serialize, Deserialize};
use chrono::{DateTime, Utc};

/// Representación de una notificación local.
#[derive(Debug, Serialize, Deserialize)]
pub struct Notification {
    pub id: i64,
    pub title: String,
    pub body: String,
    /// Epoch seconds (UTC) cuando la notificación debe mostrarse.
    pub scheduled_at: i64,
    /// JSON arbitrario con datos adicionales (por ej. id de conversación).
    pub payload: serde_json::Value,
    pub delivered: bool,
}
