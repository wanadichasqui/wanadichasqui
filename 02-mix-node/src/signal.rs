use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::response::IntoResponse;
use futures::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use crate::file_handler::NodeState;

#[derive(Deserialize)]
pub struct SignalQuery {
    pub client_id: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct SignalPayload {
    pub target_id: String,
    pub payload: String,
}

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct RoutedMessage {
    pub sender_id: String,
    pub payload: String,
}

/// Handler que acepta la conexión WebSocket upgrade con un Query parameter `client_id`.
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    Query(query): Query<SignalQuery>,
    State(state): State<NodeState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, query.client_id, state))
}

async fn handle_socket(socket: WebSocket, client_id: String, state: NodeState) {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<Message>();
    
    // Registrar el cliente
    {
        let mut clients = state.clients.lock().unwrap();
        clients.insert(client_id.clone(), tx);
    }
    
    let (mut ws_tx, ws_rx) = socket.split();
    
    // Tarea para enviar mensajes del canal al WebSocket
    let client_id_clone = client_id.clone();
    let mut send_task = tokio::spawn(async move {
        let mut rx = rx;
        while let Some(msg) = rx.recv().await {
            if let Err(e) = ws_tx.send(msg).await {
                eprintln!("WebSocket send error for {}: {}", client_id_clone, e);
                break;
            }
        }
    });

    // Bucle para leer mensajes del WebSocket y enrutarlos
    let client_id_recv = client_id.clone();
    let state_recv = state.clone();
    let mut recv_task = tokio::spawn(async move {
        let mut ws_rx = ws_rx;
        while let Some(Ok(msg)) = ws_rx.next().await {
            match msg {
                Message::Text(text) => {
                    // Intentamos parsear como acción de grupo o de sistema
                    if let Ok(val) = serde_json::from_str::<serde_json::Value>(&text) {
                        if let Some(action) = val.get("action").and_then(|a| a.as_str()) {
                            match action {
                                "create_group" => {
                                    if let (Some(g_id), Some(m_list)) = (
                                        val.get("group_id").and_then(|g| g.as_str()),
                                        val.get("members").and_then(|m| m.as_array()),
                                    ) {
                                        let members: Vec<String> = m_list
                                            .iter()
                                            .filter_map(|m| m.as_str().map(|s| s.to_string()))
                                            .collect();
                                        let mut groups = state_recv.groups.lock().unwrap();
                                        groups.insert(g_id.to_string(), members);
                                    }
                                    continue;
                                }
                                "join_group" => {
                                    if let Some(g_id) = val.get("group_id").and_then(|g| g.as_str()) {
                                        let mut groups = state_recv.groups.lock().unwrap();
                                        let entry = groups.entry(g_id.to_string()).or_insert_with(Vec::new);
                                        if !entry.contains(&client_id_recv) {
                                            entry.push(client_id_recv.clone());
                                        }
                                    }
                                    continue;
                                }
                                _ => {}
                            }
                        }
                    }

                    // Enrutamiento estándar (1-to-1 o multicast si target_id empieza por group:)
                    if let Ok(payload) = serde_json::from_str::<SignalPayload>(&text) {
                        if payload.target_id.starts_with("group:") {
                            let group_id = &payload.target_id["group:".len()..];
                            let members = {
                                let groups = state_recv.groups.lock().unwrap();
                                groups.get(group_id).cloned().unwrap_or_default()
                            };

                            let routed = RoutedMessage {
                                sender_id: client_id_recv.clone(),
                                payload: payload.payload,
                            };
                            if let Ok(routed_json) = serde_json::to_string(&routed) {
                                let clients = state_recv.clients.lock().unwrap();
                                for member in members {
                                    if member != client_id_recv {
                                        if let Some(target_tx) = clients.get(&member) {
                                            let _ = target_tx.send(Message::Text(routed_json.clone()));
                                            state_recv.messages_processed.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                                            state_recv.bytes_processed.fetch_add(routed_json.len() as u64, std::sync::atomic::Ordering::Relaxed);
                                        }
                                    }
                                }
                            }
                        } else {
                            let routed = RoutedMessage {
                                sender_id: client_id_recv.clone(),
                                payload: payload.payload,
                            };
                            if let Ok(routed_json) = serde_json::to_string(&routed) {
                                let clients = state_recv.clients.lock().unwrap();
                                if let Some(target_tx) = clients.get(&payload.target_id) {
                                    let _ = target_tx.send(Message::Text(routed_json.clone()));
                                    state_recv.messages_processed.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                                    state_recv.bytes_processed.fetch_add(routed_json.len() as u64, std::sync::atomic::Ordering::Relaxed);
                                }
                            }
                        }
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    });

    // Esperar a que termine cualquier tarea y limpiar
    tokio::select! {
        _ = &mut send_task => {
            recv_task.abort();
        }
        _ = &mut recv_task => {
            send_task.abort();
        }
    }

    // Desregistrar al cliente
    {
        let mut clients = state.clients.lock().unwrap();
        clients.remove(&client_id);
    }
}
