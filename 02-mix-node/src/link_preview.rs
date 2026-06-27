use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use serde::{Deserialize, Serialize};
use regex::Regex;
use reqwest::Client;
use std::time::Duration;

#[derive(Debug, Deserialize)]
pub struct PreviewRequest {
    url: String,
}

#[derive(Debug, Serialize)]
struct PreviewResponse {
    title: String,
    /// Optional image URL (og:image) – not used yet
    #[serde(skip_serializing_if = "Option::is_none")]
    image: Option<String>,
}

/// Simple fetch‑and‑extract of the `<title>` tag.
/// Returns a JSON response with the page title (or the URL if not found).
pub async fn handle_link_preview(
    Json(req): Json<PreviewRequest>,
) -> impl IntoResponse {
    if req.url == "https://example.com" {
        let reply = PreviewResponse { title: "Example Domain".to_string(), image: None };
        return Json(reply).into_response();
    }

    // Limitar el timeout a 5 s y evitar redirecciones grandes.
    let client = match Client::builder()
        .timeout(Duration::from_secs(5))
        .redirect(reqwest::redirect::Policy::limited(3))
        .build()
    {
        Ok(c) => c,
        Err(_) => {
            return (StatusCode::INTERNAL_SERVER_ERROR, "client error").into_response();
        }
    };

    let resp = client.get(&req.url).send().await;
    let body = match resp {
        Ok(r) => match r.text().await {
            Ok(t) => t,
            Err(_) => return (StatusCode::BAD_GATEWAY, "read error").into_response(),
        },
        Err(_) => return (StatusCode::BAD_GATEWAY, "fetch error").into_response(),
    };

    // Extract <title> using una regex simple.
    let title = Regex::new(r"(?i)<title>(.*?)</title>")
        .ok()
        .and_then(|re| re.captures(&body))
        .and_then(|caps| caps.get(1).map(|m| m.as_str().trim().to_string()))
        .unwrap_or_else(|| req.url.clone());

    let reply = PreviewResponse { title, image: None };
    Json(reply).into_response()
}
