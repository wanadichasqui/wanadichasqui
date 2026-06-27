#[cfg(test)]
mod tests {
    use crate::file_handler::NodeState;
    use crate::signal::ws_handler;
    use axum::{Router, routing::get};
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::{connect_async, tungstenite::protocol::Message as WsMessage};
    use crate::api::{
        client_initiator_start, client_responder_start, client_initiator_finish, client_responder_finish,
        client_ratchet_init, client_ratchet_encrypt, client_ratchet_decrypt
    };
    use ed25519_dalek::SigningKey;
    use rand::rngs::OsRng;
    use serde_json::json;

    #[tokio::test]
    async fn test_e2e_noise_xx_handshake() {
        // 1. Start a local Axum server with signal route on an ephemeral port
        let state = NodeState::new();
        let app = Router::new()
            .route("/signal", get(ws_handler))
            .with_state(state);
            
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });

        // 2. Connect Alice to the WebSocket
        let alice_url = format!("ws://{}/signal?client_id=alice", addr);
        let (alice_ws, _) = connect_async(alice_url).await.unwrap();
        let (mut alice_tx, mut alice_rx) = alice_ws.split();

        // 3. Connect Bob to the WebSocket
        let bob_url = format!("ws://{}/signal?client_id=bob", addr);
        let (bob_ws, _) = connect_async(bob_url).await.unwrap();
        let (mut bob_tx, mut bob_rx) = bob_ws.split();

        // 4. Generate local identity keys for Alice and Bob
        let alice_signing_key = SigningKey::generate(&mut OsRng);
        let alice_id_hex = hex::encode(alice_signing_key.to_bytes());

        let bob_signing_key = SigningKey::generate(&mut OsRng);
        let bob_id_hex = hex::encode(bob_signing_key.to_bytes());

        // 5. Alice starts: generate InitiatorHello
        let alice_start = client_initiator_start(alice_id_hex).unwrap();
        
        // Alice sends InitiatorHello payload to Bob via WebSocket
        let payload_to_bob = json!({
            "target_id": "bob",
            "payload": alice_start.e_pub_hex
        });
        alice_tx.send(WsMessage::Text(payload_to_bob.to_string())).await.unwrap();

        // 6. Bob receives InitiatorHello from Alice
        let msg = bob_rx.next().await.unwrap().unwrap();
        let text = msg.to_text().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(text).unwrap();
        assert_eq!(parsed["sender_id"], "alice");
        let alice_e_pub_hex = parsed["payload"].as_str().unwrap().to_string();

        // 7. Bob processes InitiatorHello, runs responder_start to get ResponderHello
        let bob_start = client_responder_start(bob_id_hex, alice_e_pub_hex).unwrap();
        
        // Bob sends ResponderHello payload back to Alice
        let resp_payload = json!({
            "target_id": "alice",
            "payload": json!({
                "session_id": bob_start.session_id,
                "e_pub_hex": bob_start.e_pub_hex,
                "s_pub_hex": bob_start.s_pub_hex,
                "signature_hex": bob_start.signature_hex
            }).to_string()
        });
        bob_tx.send(WsMessage::Text(resp_payload.to_string())).await.unwrap();

        // 8. Alice receives ResponderHello from Bob
        let msg = alice_rx.next().await.unwrap().unwrap();
        let text = msg.to_text().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(text).unwrap();
        assert_eq!(parsed["sender_id"], "bob");
        
        let bob_payload_val: serde_json::Value = serde_json::from_str(parsed["payload"].as_str().unwrap()).unwrap();
        let bob_session_id = bob_payload_val["session_id"].as_str().unwrap().to_string();
        let bob_e_pub_hex = bob_payload_val["e_pub_hex"].as_str().unwrap().to_string();
        let bob_s_pub_hex = bob_payload_val["s_pub_hex"].as_str().unwrap().to_string();
        let bob_signature_hex = bob_payload_val["signature_hex"].as_str().unwrap().to_string();

        // 9. Alice processes ResponderHello, runs client_initiator_finish
        let alice_finish = client_initiator_finish(
            alice_start.session_id.clone(),
            bob_e_pub_hex,
            bob_s_pub_hex,
            bob_signature_hex
        ).unwrap();

        // Alice sends InitiatorFinish back to Bob
        let finish_payload = json!({
            "target_id": "bob",
            "payload": json!({
                "session_id": bob_session_id,
                "s_pub_hex": alice_finish.s_pub_hex,
                "signature_hex": alice_finish.signature_hex
            }).to_string()
        });
        alice_tx.send(WsMessage::Text(finish_payload.to_string())).await.unwrap();

        // 10. Bob receives InitiatorFinish from Alice
        let msg = bob_rx.next().await.unwrap().unwrap();
        let text = msg.to_text().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(text).unwrap();
        assert_eq!(parsed["sender_id"], "alice");

        let alice_payload_val: serde_json::Value = serde_json::from_str(parsed["payload"].as_str().unwrap()).unwrap();
        let target_session_id = alice_payload_val["session_id"].as_str().unwrap().to_string();
        let alice_s_pub_hex = alice_payload_val["s_pub_hex"].as_str().unwrap().to_string();
        let alice_signature_hex = alice_payload_val["signature_hex"].as_str().unwrap().to_string();

        // 11. Bob runs client_responder_finish
        let bob_session_key_hex = client_responder_finish(
            target_session_id,
            alice_s_pub_hex,
            alice_signature_hex
        ).unwrap();

        // 12. Assert session keys derived on both sides match!
        assert_eq!(alice_finish.session_key_hex, bob_session_key_hex);
        assert_eq!(alice_finish.session_key_hex.len(), 64); // hex representation of 32 bytes

        // 13. Initialize RatchetState on both sides using distinct local session IDs to avoid key collision in the same process
        let alice_session_id = format!("{}_alice", alice_start.session_id);
        let bob_session_id = format!("{}_bob", alice_start.session_id);

        client_ratchet_init(alice_session_id.clone(), alice_finish.session_key_hex.clone(), true).unwrap();
        client_ratchet_init(bob_session_id.clone(), bob_session_key_hex.clone(), false).unwrap();

        // 14. Alice sends an encrypted message to Bob
        let plaintext_from_alice = "Hello Bob! This is an E2E double-ratchet encrypted message.".to_string();
        let ciphertext_hex = client_ratchet_encrypt(alice_session_id.clone(), plaintext_from_alice.clone()).unwrap();

        let encrypted_payload_to_bob = json!({
            "target_id": "bob",
            "payload": ciphertext_hex
        });
        alice_tx.send(WsMessage::Text(encrypted_payload_to_bob.to_string())).await.unwrap();

        // 15. Bob receives the encrypted message and decrypts it
        let msg = bob_rx.next().await.unwrap().unwrap();
        let text = msg.to_text().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(text).unwrap();
        assert_eq!(parsed["sender_id"], "alice");
        let received_ciphertext_hex = parsed["payload"].as_str().unwrap().to_string();

        let decrypted_by_bob = client_ratchet_decrypt(bob_session_id.clone(), received_ciphertext_hex).unwrap();
        assert_eq!(decrypted_by_bob, plaintext_from_alice);

        // 16. Bob sends an encrypted message back to Alice
        let plaintext_from_bob = "Hi Alice! I decrypted your message successfully. Replying in kind.".to_string();
        let reply_ciphertext_hex = client_ratchet_encrypt(bob_session_id.clone(), plaintext_from_bob.clone()).unwrap();

        let encrypted_payload_to_alice = json!({
            "target_id": "alice",
            "payload": reply_ciphertext_hex
        });
        bob_tx.send(WsMessage::Text(encrypted_payload_to_alice.to_string())).await.unwrap();

        // 17. Alice receives the reply and decrypts it
        let msg = alice_rx.next().await.unwrap().unwrap();
        let text = msg.to_text().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(text).unwrap();
        assert_eq!(parsed["sender_id"], "bob");
        let received_reply_ciphertext_hex = parsed["payload"].as_str().unwrap().to_string();

        let decrypted_by_alice = client_ratchet_decrypt(alice_session_id.clone(), received_reply_ciphertext_hex).unwrap();
        assert_eq!(decrypted_by_alice, plaintext_from_bob);
    }
}
