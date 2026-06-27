use std::net::IpAddr;
use std::str::FromStr;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct Config {
    pub host: IpAddr,
    pub port: u16,
    pub db_path: String,
    pub tls_cert: Option<String>,
    pub tls_key: Option<String>,
    pub dummy_interval_ms: u64,
}

impl Config {
    pub fn from_env() -> Self {
        // Intentar leer opcionalmente un archivo "config.env" local si existe
        if Path::new("config.env").exists() {
            if let Ok(content) = std::fs::read_to_string("config.env") {
                for line in content.lines() {
                    let line = line.trim();
                    if line.is_empty() || line.starts_with('#') {
                        continue;
                    }
                    if let Some((key, value)) = line.split_once('=') {
                        let key = key.trim();
                        let value = value.trim().trim_matches('"').trim_matches('\'');
                        std::env::set_var(key, value);
                    }
                }
            }
        }

        let host_str = std::env::var("WANADI_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
        let host = IpAddr::from_str(&host_str).unwrap_or_else(|_| IpAddr::from([0, 0, 0, 0]));

        let port_str = std::env::var("WANADI_PORT").unwrap_or_else(|_| "8000".to_string());
        let port = u16::from_str(&port_str).unwrap_or(8000);

        let db_path = std::env::var("WANADI_BLOB_DB").unwrap_or_else(|_| "mix_node_blobs.db".to_string());

        let tls_cert = std::env::var("WANADI_TLS_CERT").ok();
        let tls_key = std::env::var("WANADI_TLS_KEY").ok();

        let dummy_interval_str = std::env::var("WANADI_DUMMY_INTERVAL_MS").unwrap_or_else(|_| "5000".to_string());
        let dummy_interval_ms = u64::from_str(&dummy_interval_str).unwrap_or(5000);

        Self {
            host,
            port,
            db_path,
            tls_cert,
            tls_key,
            dummy_interval_ms,
        }
    }
}
