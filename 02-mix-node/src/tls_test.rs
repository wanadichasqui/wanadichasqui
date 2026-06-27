#[cfg(test)]
mod tests {
    use crate::file_handler::NodeState;
    use axum::{Router, routing::get};
    use axum_server::tls_rustls::RustlsConfig;
    use rcgen::generate_simple_self_signed;

    #[tokio::test]
    async fn test_tls_server_health() {
        // Asegurar que el CryptoProvider de rustls esté instalado
        rustls::crypto::ring::default_provider()
            .install_default()
            .ok();

        // 1. Crear el Router
        let state = NodeState::new();
        let app = Router::new()
            .route("/health", get(|| async { "OK" }))
            .with_state(state);

        // 2. Generar certificado autofirmado dinámico
        let subject_alt_names = vec!["localhost".to_string(), "127.0.0.1".to_string()];
        let rcgen::CertifiedKey { cert, key_pair } = generate_simple_self_signed(subject_alt_names).unwrap();
        let cert_pem = cert.pem();
        let key_pem = key_pair.serialize_pem();

        let config = RustlsConfig::from_pem(cert_pem.into_bytes(), key_pem.into_bytes())
            .await
            .unwrap();

        // 3. Crear el listener TCP manualmente para un puerto efímero
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let local_addr = listener.local_addr().unwrap();

        // Lanzar el servidor TLS en segundo plano usando from_tcp_rustls
        tokio::spawn(async move {
            axum_server::from_tcp_rustls(listener, config)
                .serve(app.into_make_service())
                .await
                .unwrap();
        });

        // 4. Conectar usando un cliente HTTPS que acepte certificados autofirmados
        let client = reqwest::Client::builder()
            .danger_accept_invalid_certs(true)
            .build()
            .unwrap();

        let url = format!("https://{}/health", local_addr);
        let res = client.get(&url).send().await.unwrap();
        
        assert_eq!(res.status(), reqwest::StatusCode::OK);
        let body = res.text().await.unwrap();
        assert_eq!(body, "OK");
    }
}
