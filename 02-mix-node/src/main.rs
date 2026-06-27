mod file_handler;
mod link_preview;
mod signal;
mod node_auth;
mod config;

use axum::{Router, routing::{get, post}, middleware};
use file_handler::NodeState;
use node_auth::NodeRegistry;
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    // Inicializar el suscriptor de tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .init();

    // Instalar el CryptoProvider global para rustls (usando ring)
    rustls::crypto::ring::default_provider()
        .install_default()
        .ok();

    // Cargar configuración externa
    let app_config = config::Config::from_env();

    // Estado compartido (BlobStore persistente en SQLite)
    let state = NodeState::new_persistent(app_config.db_path.clone());

    // Registro de nodos autorizados (modo abierto por defecto).
    let registry = NodeRegistry::new();

    // Rutas protegidas por autenticación de nodos (inter‑nodo)
    let protected = Router::new()
        .route("/file_chunk", post(file_handler::handle_file_chunk))
        .route("/link_preview", post(link_preview::handle_link_preview))
        .layer(middleware::from_fn_with_state(
            registry.clone(),
            node_auth::verify_node_signature,
        ))
        .with_state(state.clone());

    // Rutas públicas (health check, señalización WebSocket para clientes)
    let public = Router::new()
        .route("/health", get(|| async { "OK" }))
        .route("/signal", get(signal::ws_handler))
        .route("/metrics", get(metrics_handler))
        .with_state(state.clone());

    // Tráfico de cobertura real (Área 3)
    let dummy_interval = app_config.dummy_interval_ms;
    let state_dummy = state.clone();
    tokio::spawn(async move {
        tracing::info!("Starting coverage traffic scheduler (interval: {}ms)", dummy_interval);
        let mut interval = tokio::time::interval(std::time::Duration::from_millis(dummy_interval));
        loop {
            interval.tick().await;
            
            // Obtener los IDs de los clientes actualmente conectados
            let active_clients: Vec<String> = {
                let clients_guard = state_dummy.clients.lock().unwrap();
                clients_guard.keys().cloned().collect()
            };

            if !active_clients.is_empty() {
                // Seleccionar un cliente activo aleatorio para enviarle un paquete dummy
                use rand::seq::SliceRandom;
                let mut rng = rand::thread_rng();
                if let Some(target) = active_clients.choose(&mut rng) {
                    let dummy_payload = serde_json::json!({
                        "type": "dummy",
                        "noise": "random_bytes_obfuscation"
                    }).to_string();

                    let routed = signal::RoutedMessage {
                        sender_id: "system_cover".to_string(),
                        payload: dummy_payload,
                    };

                    if let Ok(routed_json) = serde_json::to_string(&routed) {
                        let clients = state_dummy.clients.lock().unwrap();
                        if let Some(target_tx) = clients.get(target) {
                            tracing::debug!("Sending coverage traffic dummy packet to client: {}", target);
                            let _ = target_tx.send(axum::extract::ws::Message::Text(routed_json));
                        }
                    }
                }
            }
        }
    });

    // Componer el router final
    let app = Router::new().merge(public).merge(protected);

    let addr = SocketAddr::new(app_config.host, app_config.port);

    // Configuración de TLS
    let config = if let (Some(c_path), Some(k_path)) = (&app_config.tls_cert, &app_config.tls_key) {
        tracing::info!("Loading TLS certificate from {} and private key from {}", c_path, k_path);
        axum_server::tls_rustls::RustlsConfig::from_pem_file(c_path, k_path)
            .await
            .expect("failed to load TLS cert/key files")
    } else {
        tracing::warn!("No WANADI_TLS_CERT/WANADI_TLS_KEY configured. Generating dynamic self-signed certificate...");
        let subject_alt_names = vec!["localhost".to_string(), "127.0.0.1".to_string()];
        let rcgen::CertifiedKey { cert, key_pair } = rcgen::generate_simple_self_signed(subject_alt_names)
            .expect("failed to generate self-signed cert");
        let cert_pem = cert.pem();
        let key_pem = key_pair.serialize_pem();

        axum_server::tls_rustls::RustlsConfig::from_pem(cert_pem.into_bytes(), key_pem.into_bytes())
            .await
            .expect("failed to create RustlsConfig from generated cert")
    };

    tracing::info!("Mix‑node listening with TLS on {}", addr);

    axum_server::bind_rustls(addr, config)
        .serve(app.into_make_service())
        .await
        .expect("server error");
}

async fn metrics_handler(axum::extract::State(state): axum::extract::State<NodeState>) -> impl axum::response::IntoResponse {
    use std::sync::atomic::Ordering;
    let msgs = state.messages_processed.load(Ordering::Relaxed);
    let bytes = state.bytes_processed.load(Ordering::Relaxed);
    let active_clients = state.clients.lock().unwrap().len();

    let body = format!(
        "# HELP wanadi_messages_processed_total Total number of routed signals and file chunks processed by the mix-node\n\
         # TYPE wanadi_messages_processed_total counter\n\
         wanadi_messages_processed_total {}\n\n\
         # HELP wanadi_bytes_processed_total Total bytes routed or received by the mix-node\n\
         # TYPE wanadi_bytes_processed_total counter\n\
         wanadi_bytes_processed_total {}\n\n\
         # HELP wanadi_active_clients Current number of active WebSocket signaling connections\n\
         # TYPE wanadi_active_clients gauge\n\
         wanadi_active_clients {}\n",
        msgs, bytes, active_clients
    );

    (
        [(axum::http::header::CONTENT_TYPE, "text/plain; version=0.0.4; charset=utf-8")],
        body,
    )
}
