#[cfg(test)]
mod tests {
    use crate::link_preview::handle_link_preview;
    use axum::{routing::post, Router};
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use tower::ServiceExt;
    use serde_json::json;

    #[tokio::test]
    async fn test_link_preview_example() {
        let app = Router::new()
            .route("/link_preview", post(handle_link_preview));

        let payload = json!({ "url": "https://example.com" });
        let request = Request::builder()
            .method("POST")
            .uri("/link_preview")
            .header("content-type", "application/json")
            .body(Body::from(serde_json::to_vec(&payload).unwrap()))
            .unwrap();

        let resp = app.oneshot(request).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);

        let body = axum::body::to_bytes(resp.into_body(), usize::MAX).await.unwrap();
        let json_val: serde_json::Value = serde_json::from_slice(&body).expect("valid json");
        // El título de https://example.com es siempre "Example Domain"
        assert_eq!(json_val["title"], "Example Domain");
    }
}
