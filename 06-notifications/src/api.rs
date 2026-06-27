use std::path::PathBuf;
use flutter_rust_bridge::frb;
use storage::open_encrypted_db;
use crate::models::Notification;
use rusqlite::params;

/// Inicializa la tabla `notificaciones` dentro de la base de datos cifrada SQLite.
#[frb]
pub fn init_notification_schema(db_path: String, password: String) -> Result<(), String> {
    let conn = open_encrypted_db(&PathBuf::from(db_path), &password).map_err(|e| e.to_string())?;
    conn.execute(
        "CREATE TABLE IF NOT EXISTS notificaciones (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            title        TEXT NOT NULL,
            body         TEXT NOT NULL,
            scheduled_at INTEGER NOT NULL,
            payload      TEXT,
            delivered    INTEGER NOT NULL DEFAULT 0
        )",
        params![],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

/// Añade o programa una notificación en la base de datos.
#[frb]
pub fn add_notification(
    db_path: String,
    password: String,
    title: String,
    body: String,
    scheduled_at: i64,
    payload: String,
) -> Result<(), String> {
    let conn = open_encrypted_db(&PathBuf::from(db_path), &password).map_err(|e| e.to_string())?;
    conn.execute(
        "INSERT INTO notificaciones (title, body, scheduled_at, payload, delivered)
         VALUES (?1, ?2, ?3, ?4, 0)",
        params![title, body, scheduled_at, payload],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

/// Recupera todas las notificaciones pendientes de entregar cuya fecha programada sea menor o igual al timestamp dado.
#[frb]
pub fn get_undelivered_notifications(db_path: String, password: String, now: i64) -> Result<Vec<Notification>, String> {
    let conn = open_encrypted_db(&PathBuf::from(db_path), &password).map_err(|e| e.to_string())?;
    let mut stmt = conn
        .prepare("SELECT id, title, body, scheduled_at, payload, delivered FROM notificaciones WHERE delivered = 0 AND scheduled_at <= ?1")
        .map_err(|e| e.to_string())?;
    
    let rows = stmt.query_map(params![now], |row| {
        let payload_str: Option<String> = row.get(4)?;
        let payload_val = match payload_str {
            Some(ref s) => serde_json::from_str(s).unwrap_or(serde_json::Value::Null),
            None => serde_json::Value::Null,
        };
        Ok(Notification {
            id: row.get(0)?,
            title: row.get(1)?,
            body: row.get(2)?,
            scheduled_at: row.get(3)?,
            payload: payload_val,
            delivered: row.get::<_, i32>(5)? != 0,
        })
    }).map_err(|e| e.to_string())?;

    let mut list = Vec::new();
    for r in rows {
        list.push(r.map_err(|e| e.to_string())?);
    }
    Ok(list)
}

/// Marca una notificación específica como entregada.
#[frb]
pub fn mark_as_delivered(db_path: String, password: String, id: i64) -> Result<(), String> {
    let conn = open_encrypted_db(&PathBuf::from(db_path), &password).map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE notificaciones SET delivered = 1 WHERE id = ?1",
        params![id],
    ).map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn test_notifications_flow() {
        let temp_file = NamedTempFile::new().unwrap();
        let db_path = temp_file.path().to_string_lossy().to_string();
        let password = "test-password-123".to_string();

        // 1. Init schema
        init_notification_schema(db_path.clone(), password.clone()).unwrap();

        // 2. Add notifications
        add_notification(
            db_path.clone(),
            password.clone(),
            "Title 1".to_string(),
            "Body 1".to_string(),
            100,
            "{\"chat_id\": 1}".to_string(),
        ).unwrap();

        add_notification(
            db_path.clone(),
            password.clone(),
            "Title 2".to_string(),
            "Body 2".to_string(),
            200,
            "{\"chat_id\": 2}".to_string(),
        ).unwrap();

        // 3. Get undelivered notifications at time 150 (only first should be returned)
        let undelivered = get_undelivered_notifications(db_path.clone(), password.clone(), 150).unwrap();
        assert_eq!(undelivered.len(), 1);
        assert_eq!(undelivered[0].title, "Title 1");
        assert_eq!(undelivered[0].body, "Body 1");
        assert_eq!(undelivered[0].scheduled_at, 100);
        assert_eq!(undelivered[0].delivered, false);

        // 4. Mark first as delivered
        mark_as_delivered(db_path.clone(), password.clone(), undelivered[0].id).unwrap();

        // 5. Get undelivered at time 150 again (should be 0)
        let undelivered = get_undelivered_notifications(db_path.clone(), password.clone(), 150).unwrap();
        assert_eq!(undelivered.len(), 0);

        // 6. Get undelivered at time 250 (should return the second one)
        let undelivered = get_undelivered_notifications(db_path.clone(), password.clone(), 250).unwrap();
        assert_eq!(undelivered.len(), 1);
        assert_eq!(undelivered[0].title, "Title 2");
        assert_eq!(undelivered[0].delivered, false);
    }
}

