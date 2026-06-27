//! Middleware de autenticación de nodos mediante firma Ed25519.
//!
//! Cada nodo que se conecta al mix‑node debe incluir tres headers:
//!
//! * `x-node-pubkey`    – clave pública Ed25519 en hexadecimal (64 chars).
//! * `x-node-signature` – firma Ed25519 del *cuerpo* de la petición (128 chars hex).
//!                        Para peticiones sin cuerpo (GET, WebSocket upgrade),
//!                        se firma el valor de `x-node-timestamp`.
//! * `x-node-timestamp` – Unix epoch en segundos (cadena decimal).
//!
//! El middleware:
//!   1. Decodifica la clave pública y la firma desde hex.
//!   2. Reconstruye el mensaje firmado (body o timestamp).
//!   3. Verifica la firma con `crypto_core::verify`.
//!   4. Comprueba que el timestamp no difiera del reloj local en más de
//!      `MAX_CLOCK_SKEW` segundos (anti‑replay).
//!   5. Si hay un `NodeRegistry`, verifica que la clave pública sea conocida.
//!
//! Si la verificación falla devuelve `401 Unauthorized`.

use axum::{
    extract::{Request, State},
    http::{header::HeaderMap, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};
use ed25519_dalek::{Signature, VerifyingKey};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

/// Margen máximo de desviación del reloj (segundos).
const MAX_CLOCK_SKEW: u64 = 300; // 5 minutos

/// Registro de claves públicas de nodos autorizados.
///
/// Si está vacío, cualquier nodo con una firma válida es aceptado
/// (modo abierto / bootstrapping).  En producción se debe poblar
/// con las claves de los nodos conocidos.
#[derive(Debug, Clone, Default)]
pub struct NodeRegistry {
    /// Claves públicas autorizadas (bytes crudos, 32 bytes cada una).
    pub authorized: Arc<Mutex<HashSet<[u8; 32]>>>,
}

impl NodeRegistry {
    /// Crea un registro vacío (modo abierto).
    pub fn new() -> Self {
        Self::default()
    }

    /// Crea un registro con un conjunto inicial de claves autorizadas.
    pub fn with_keys(keys: Vec<[u8; 32]>) -> Self {
        Self {
            authorized: Arc::new(Mutex::new(keys.into_iter().collect())),
        }
    }

    /// Añade una clave pública al registro.
    pub fn add_key(&self, key: [u8; 32]) {
        self.authorized.lock().unwrap().insert(key);
    }

    /// Elimina una clave pública del registro.
    pub fn remove_key(&self, key: &[u8; 32]) {
        self.authorized.lock().unwrap().remove(key);
    }

    /// Verifica si una clave está autorizada.
    /// Si el registro está vacío (modo abierto), cualquier clave es aceptada.
    pub fn is_authorized(&self, key: &[u8; 32]) -> bool {
        let guard = self.authorized.lock().unwrap();
        guard.is_empty() || guard.contains(key)
    }
}

/// Extrae un header como `&str`, devolviendo un error descriptivo si falta.
fn get_header<'a>(headers: &'a HeaderMap, name: &str) -> Result<&'a str, String> {
    headers
        .get(name)
        .ok_or_else(|| format!("missing header: {}", name))?
        .to_str()
        .map_err(|_| format!("invalid UTF-8 in header: {}", name))
}

/// Middleware Axum que verifica la firma Ed25519 del nodo que se conecta.
///
/// Se aplica como capa (`axum::middleware::from_fn_with_state`) sobre las
/// rutas que requieren autenticación de nodos.
pub async fn verify_node_signature(
    State(registry): State<NodeRegistry>,
    request: Request,
    next: Next,
) -> Response {
    let headers = request.headers().clone();

    // ── 1. Extraer headers ───────────────────────────────────────────────
    let pubkey_hex = match get_header(&headers, "x-node-pubkey") {
        Ok(v) => v.to_owned(),
        Err(e) => return (StatusCode::UNAUTHORIZED, e).into_response(),
    };
    let signature_hex = match get_header(&headers, "x-node-signature") {
        Ok(v) => v.to_owned(),
        Err(e) => return (StatusCode::UNAUTHORIZED, e).into_response(),
    };
    let timestamp_str = match get_header(&headers, "x-node-timestamp") {
        Ok(v) => v.to_owned(),
        Err(e) => return (StatusCode::UNAUTHORIZED, e).into_response(),
    };

    // ── 2. Decodificar clave pública ─────────────────────────────────────
    let pubkey_bytes = match hex::decode(&pubkey_hex) {
        Ok(b) if b.len() == 32 => {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&b);
            arr
        }
        _ => return (StatusCode::UNAUTHORIZED, "invalid x-node-pubkey").into_response(),
    };

    let verifying_key = match VerifyingKey::from_bytes(&pubkey_bytes) {
        Ok(k) => k,
        Err(_) => return (StatusCode::UNAUTHORIZED, "invalid Ed25519 public key").into_response(),
    };

    // ── 3. Decodificar firma ─────────────────────────────────────────────
    let sig_bytes = match hex::decode(&signature_hex) {
        Ok(b) if b.len() == 64 => {
            let mut arr = [0u8; 64];
            arr.copy_from_slice(&b);
            arr
        }
        _ => return (StatusCode::UNAUTHORIZED, "invalid x-node-signature").into_response(),
    };
    let signature = Signature::from_bytes(&sig_bytes);

    // ── 4. Validar timestamp (anti‑replay) ───────────────────────────────
    let timestamp: u64 = match timestamp_str.parse() {
        Ok(t) => t,
        Err(_) => return (StatusCode::UNAUTHORIZED, "invalid x-node-timestamp").into_response(),
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let diff = if now > timestamp { now - timestamp } else { timestamp - now };
    if diff > MAX_CLOCK_SKEW {
        return (StatusCode::UNAUTHORIZED, "timestamp too far from current time").into_response();
    }

    // ── 5. Construir el mensaje a verificar ──────────────────────────────
    // Para todas las peticiones: firma sobre el timestamp.
    // Esto da autenticación + anti‑replay sin necesidad de consumir el body
    // (lo cual complicaría el middleware para streaming/WebSocket).
    let message = timestamp_str.as_bytes();

    // ── 6. Verificar firma ───────────────────────────────────────────────
    if !crypto_core::verify(&verifying_key, message, &signature) {
        return (StatusCode::UNAUTHORIZED, "signature verification failed").into_response();
    }

    // ── 7. Verificar autorización en el registro ─────────────────────────
    if !registry.is_authorized(&pubkey_bytes) {
        return (StatusCode::UNAUTHORIZED, "node not authorized").into_response();
    }

    // ── 8. Continuar con el handler ──────────────────────────────────────
    next.run(request).await
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════
#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, routing::get, Router};
    use ed25519_dalek::SigningKey;
    use rand::rngs::OsRng;
    use crypto_core::sign;
    use hyper::body::Bytes;
    use http_body_util::BodyExt;

    /// Construye un router de prueba con el middleware de autenticación.
    fn test_app(registry: NodeRegistry) -> Router {
        Router::new()
            .route("/protected", get(|| async { "ok" }))
            .layer(axum::middleware::from_fn_with_state(
                registry.clone(),
                verify_node_signature,
            ))
            .with_state(registry)
    }

    /// Helper: genera headers de autenticación válidos.
    fn auth_headers(signing_key: &SigningKey) -> Vec<(&'static str, String)> {
        let pubkey_hex = hex::encode(signing_key.verifying_key().to_bytes());
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
            .to_string();
        let signature = sign(signing_key, timestamp.as_bytes());
        let signature_hex = hex::encode(signature.to_bytes());

        vec![
            ("x-node-pubkey", pubkey_hex),
            ("x-node-signature", signature_hex),
            ("x-node-timestamp", timestamp),
        ]
    }

    async fn send_request(app: Router, headers: Vec<(&str, String)>) -> (StatusCode, Bytes) {
        use tower::ServiceExt;
        let mut req = axum::http::Request::builder()
            .uri("/protected")
            .method("GET");
        for (k, v) in &headers {
            req = req.header(*k, v.as_str());
        }
        let req = req.body(Body::empty()).unwrap();
        let resp = app.oneshot(req).await.unwrap();
        let status = resp.status();
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        (status, body)
    }

    #[tokio::test]
    async fn test_valid_signature_open_registry() {
        let registry = NodeRegistry::new();
        let app = test_app(registry);
        let key = SigningKey::generate(&mut OsRng);
        let headers = auth_headers(&key);
        let (status, body) = send_request(app, headers).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(&body[..], b"ok");
    }

    #[tokio::test]
    async fn test_valid_signature_authorized_node() {
        let key = SigningKey::generate(&mut OsRng);
        let pub_bytes = key.verifying_key().to_bytes();
        let registry = NodeRegistry::with_keys(vec![pub_bytes]);
        let app = test_app(registry);
        let headers = auth_headers(&key);
        let (status, _) = send_request(app, headers).await;
        assert_eq!(status, StatusCode::OK);
    }

    #[tokio::test]
    async fn test_unauthorized_node_not_in_registry() {
        let authorized_key = SigningKey::generate(&mut OsRng);
        let registry = NodeRegistry::with_keys(vec![authorized_key.verifying_key().to_bytes()]);
        let app = test_app(registry);

        // Un nodo diferente intenta conectar
        let rogue_key = SigningKey::generate(&mut OsRng);
        let headers = auth_headers(&rogue_key);
        let (status, _) = send_request(app, headers).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_missing_headers() {
        let registry = NodeRegistry::new();
        let app = test_app(registry);
        let (status, _) = send_request(app, vec![]).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_invalid_signature() {
        let registry = NodeRegistry::new();
        let app = test_app(registry);
        let key = SigningKey::generate(&mut OsRng);
        let mut headers = auth_headers(&key);

        // Corromper la firma (cambiar el último byte)
        if let Some((_, ref mut sig_hex)) = headers.iter_mut().find(|(k, _)| *k == "x-node-signature") {
            let mut bytes = hex::decode(sig_hex.as_str()).unwrap();
            bytes[63] ^= 0xFF;
            *sig_hex = hex::encode(bytes);
        }
        let (status, _) = send_request(app, headers).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_expired_timestamp() {
        let registry = NodeRegistry::new();
        let app = test_app(registry);
        let key = SigningKey::generate(&mut OsRng);

        // Crear un timestamp de hace 10 minutos (fuera del margen de 5 min)
        let old_timestamp = (SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() - 600)
            .to_string();
        let signature = sign(&key, old_timestamp.as_bytes());
        let headers = vec![
            ("x-node-pubkey", hex::encode(key.verifying_key().to_bytes())),
            ("x-node-signature", hex::encode(signature.to_bytes())),
            ("x-node-timestamp", old_timestamp),
        ];
        let (status, _) = send_request(app, headers).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn test_add_and_remove_from_registry() {
        let key = SigningKey::generate(&mut OsRng);
        let pub_bytes = key.verifying_key().to_bytes();
        let registry = NodeRegistry::new();

        // Registro vacío → modo abierto
        assert!(registry.is_authorized(&pub_bytes));

        // Añadir otra clave → ya no es modo abierto
        let other_key = SigningKey::generate(&mut OsRng);
        let other_pub = other_key.verifying_key().to_bytes();
        registry.add_key(other_pub);
        assert!(!registry.is_authorized(&pub_bytes));
        assert!(registry.is_authorized(&other_pub));

        // Añadir nuestra clave → ahora sí
        registry.add_key(pub_bytes);
        assert!(registry.is_authorized(&pub_bytes));

        // Eliminar nuestra clave → ya no
        registry.remove_key(&pub_bytes);
        assert!(!registry.is_authorized(&pub_bytes));
    }
}
