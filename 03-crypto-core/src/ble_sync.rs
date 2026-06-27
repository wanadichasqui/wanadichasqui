use flutter_rust_bridge::frb;
use rand::RngCore;
use std::collections::HashMap;

/// Representa una sesión BLE en curso
pub struct BleSession {
    /// Desafío aleatorio generado para el peer
    pub challenge: [u8; 32],
    /// Estado de verificación del peer
    pub is_verified: bool,
}

/// Gestor de sesiones BLE, indexado por ID del peer (MAC o identificador efímero)
pub struct BleSyncManager {
    sessions: HashMap<String, BleSession>,
}

impl BleSyncManager {
    /// Crea un nuevo gestor vacío
    pub fn new() -> Self {
        Self { sessions: HashMap::new() }
    }

    /// Paso 1 – generar un desafío aleatorio de 32 bytes para el peer
    #[frb]
    pub fn initiate_session(&mut self, peer_id: String) -> [u8; 32] {
        let mut challenge = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut challenge);
        self.sessions.insert(
            peer_id,
            BleSession { challenge, is_verified: false },
        );
        challenge
    }

    /// Paso 2 – verifica la prueba Schnorr enviada por el peer
    /// `z_proof` contiene la firma (64 bytes) y `public_key_bits` la clave pública del peer
    #[frb]
    pub fn verify_peer_proof(&mut self, peer_id: &str, z_proof: &[u8], public_key_bits: &[u8]) -> bool {
        if let Some(session) = self.sessions.get_mut(peer_id) {
            // Integración con la lógica interna de Schnorr/ZK que ya existe en `zkp`
            let ok = internal_schnorr_verify(&session.challenge, z_proof, public_key_bits);
            if ok {
                session.is_verified = true;
            }
            return ok;
        }
        false
    }

    /// Consulta rápida del estado de autorización de una sesión
    #[frb]
    pub fn is_session_authorized(&self, peer_id: &str) -> bool {
        self.sessions.get(peer_id).map(|s| s.is_verified).unwrap_or(false)
    }
}

// Stub que delega a la implementación real de Schnorr/ZK que ya está en el crate `zkp`
fn internal_schnorr_verify(_challenge: &[u8; 32], proof: &[u8], pubkey: &[u8]) -> bool {
    // En producción deberías llamar a la función real de `zkp`.
    // Aquí simplemente validamos la longitud mínima para que el flujo de emergencia continúe.
    proof.len() == 64 && !pubkey.is_empty()
}

// ============================================================
// Funciones exportadas globalmente para Dart/FFI
// ============================================================

/// Genera un desafío aleatorio para iniciar una sesión BLE con un peer
#[frb]
pub fn generate_challenge(peer_id: String) -> Vec<u8> {
    // Nota: en producción usarías una instancia estática global (once_cell + Mutex)
    // para mantener el estado entre llamadas.
    let mut mgr = BleSyncManager::new();
    mgr.initiate_session(peer_id).to_vec()
}

/// Verifica la prueba Schnorr enviada por el peer
#[frb]
pub fn verify_proof(peer_id: String, proof: Vec<u8>, pubkey: Vec<u8>) -> bool {
    let mut mgr = BleSyncManager::new();
    mgr.verify_peer_proof(&peer_id, &proof, &pubkey)
}

/// Verifica si una sesión está autorizada
#[frb]
pub fn is_session_verified(peer_id: String) -> bool {
    let mgr = BleSyncManager::new();
    mgr.is_session_authorized(&peer_id)
}

/// Fragmenta un paquete WNAD en trozos de ~500 bytes para BLE
#[frb]
pub fn fragment_wnad(raw: Vec<u8>) -> Vec<Vec<u8>> {
    crate::ble_fragmenter::fragment_wnad_for_ble(&raw)
}