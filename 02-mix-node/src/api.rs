use flutter_rust_bridge::frb;
use wire_protocol::{FileChunk, compute_file_id, Packet, MessageType};
use reqwest::blocking::Client;
use hex;

#[frb]
pub fn send_file_chunk(chunk_bytes: Vec<u8>) -> Result<String, String> {
    // Derivar file_id (SHA‑256) del payload completo
    let file_id = compute_file_id(&chunk_bytes);
    // Construir un único FileChunk (para MVP)
    let chunk = FileChunk {
        file_id,
        chunk_index: 0,
        total_chunks: 1,
        data: chunk_bytes.into(),
    };
    // Empaquetar en nuestro protocolo binario
    let packet = Packet::new(MessageType::FileChunk, chunk.encode());
    let payload = packet.encode();

    // Enviar vía HTTP síncrono al nodo local
    let client = Client::new();
    let resp = client
        .post("http://localhost:8000/file_chunk")
        .body(payload)
        .send()
        .map_err(|e| e.to_string())?;

    resp.text().map_err(|e| e.to_string())
}

#[frb]
pub fn get_encryption_key(priv_key_hex: String) -> Result<String, String> {
    // Decodificar la clave privada en hexadecimal (32 bytes)
    let bytes = hex::decode(&priv_key_hex).map_err(|e| e.to_string())?;
    if bytes.len() != 32 {
        return Err("private key must be 32 bytes".into());
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    // Derivamos una clave de cifrado usando HKDF‑SHA256 vía crypto_core
    let key = crypto_core::derive_keys(&arr, b"wanadi-chasqui-encryption")
        .map_err(|e| e.to_string())?;
    Ok(hex::encode(key))
}

use std::sync::{Mutex, OnceLock};
use std::collections::HashMap;
use crypto_core::handshake::{
    initiator_hello, responder_hello, initiator_finish, responder_finish,
    InitiatorState, ResponderState, InitiatorHello, ResponderHello, InitiatorFinish,
};
use crypto_core::{MlsGroupSession, WelcomeMessage, EncryptedGroupMessage};
use ed25519_dalek::{SigningKey, VerifyingKey, Signature};
use x25519_dalek::PublicKey as X25519PublicKey;
use crypto_core::key_agreement::CryptoError;

static INITIATOR_STATES: OnceLock<Mutex<HashMap<String, InitiatorState>>> = OnceLock::new();
static RESPONDER_STATES: OnceLock<Mutex<HashMap<String, ResponderState>>> = OnceLock::new();

fn get_initiator_states() -> &'static Mutex<HashMap<String, InitiatorState>> {
    INITIATOR_STATES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn get_responder_states() -> &'static Mutex<HashMap<String, ResponderState>> {
    RESPONDER_STATES.get_or_init(|| Mutex::new(HashMap::new()))
}

#[frb]
#[derive(Debug, Clone)]
pub struct HandshakeStartResult {
    pub session_id: String,
    pub e_pub_hex: String,
}

#[frb]
#[derive(Debug, Clone)]
pub struct HandshakeResponderResult {
    pub session_id: String,
    pub e_pub_hex: String,
    pub s_pub_hex: String,
    pub signature_hex: String,
}

#[frb]
#[derive(Debug, Clone)]
pub struct HandshakeInitiatorFinishResult {
    pub s_pub_hex: String,
    pub signature_hex: String,
    pub session_key_hex: String,
}

#[frb]
pub fn client_initiator_start(id_hex: String) -> Result<HandshakeStartResult, String> {
    let id_bytes = hex::decode(&id_hex).map_err(|e| e.to_string())?;
    if id_bytes.len() != 32 {
        return Err("private key must be 32 bytes".into());
    }
    let mut id_arr = [0u8; 32];
    id_arr.copy_from_slice(&id_bytes);
    let id = SigningKey::from_bytes(&id_arr);

    let (state, hello) = initiator_hello(&id);
    let session_id = hex::encode(rand::random::<[u8; 16]>());

    get_initiator_states().lock().unwrap().insert(session_id.clone(), state);

    Ok(HandshakeStartResult {
        session_id,
        e_pub_hex: hex::encode(hello.e_pub.as_bytes()),
    })
}

#[frb]
pub fn client_responder_start(id_hex: String, initiator_e_pub_hex: String) -> Result<HandshakeResponderResult, String> {
    let id_bytes = hex::decode(&id_hex).map_err(|e| e.to_string())?;
    if id_bytes.len() != 32 {
        return Err("private key must be 32 bytes".into());
    }
    let mut id_arr = [0u8; 32];
    id_arr.copy_from_slice(&id_bytes);
    let id = SigningKey::from_bytes(&id_arr);

    let init_e_pub_bytes = hex::decode(&initiator_e_pub_hex).map_err(|e| e.to_string())?;
    if init_e_pub_bytes.len() != 32 {
        return Err("initiator e_pub must be 32 bytes".into());
    }
    let mut init_e_pub_arr = [0u8; 32];
    init_e_pub_arr.copy_from_slice(&init_e_pub_bytes);
    let init_e_pub = X25519PublicKey::from(init_e_pub_arr);

    let hello = InitiatorHello { e_pub: init_e_pub };
    let (state, response) = responder_hello(&id, &hello)
        .map_err(|e| e.to_string())?;
    let session_id = hex::encode(rand::random::<[u8; 16]>());

    get_responder_states().lock().unwrap().insert(session_id.clone(), state);

    Ok(HandshakeResponderResult {
        session_id,
        e_pub_hex: hex::encode(response.e_pub.as_bytes()),
        s_pub_hex: hex::encode(response.s_pub.to_bytes()),
        signature_hex: hex::encode(response.signature.to_bytes()),
    })
}

#[frb]
pub fn client_initiator_finish(
    session_id: String,
    responder_e_pub_hex: String,
    responder_s_pub_hex: String,
    responder_signature_hex: String,
) -> Result<HandshakeInitiatorFinishResult, String> {
    let state = get_initiator_states()
        .lock()
        .unwrap()
        .remove(&session_id)
        .ok_or_else(|| "handshake session not found".to_string())?;

    let resp_e_bytes = hex::decode(&responder_e_pub_hex).map_err(|e| e.to_string())?;
    if resp_e_bytes.len() != 32 {
        return Err("responder e_pub must be 32 bytes".into());
    }
    let mut resp_e_arr = [0u8; 32];
    resp_e_arr.copy_from_slice(&resp_e_bytes);
    let resp_e = X25519PublicKey::from(resp_e_arr);

    let resp_s_bytes = hex::decode(&responder_s_pub_hex).map_err(|e| e.to_string())?;
    if resp_s_bytes.len() != 32 {
        return Err("responder s_pub must be 32 bytes".into());
    }
    let mut resp_s_arr = [0u8; 32];
    resp_s_arr.copy_from_slice(&resp_s_bytes);
    let resp_s = VerifyingKey::from_bytes(&resp_s_arr).map_err(|e| e.to_string())?;

    let resp_sig_bytes = hex::decode(&responder_signature_hex).map_err(|e| e.to_string())?;
    if resp_sig_bytes.len() != 64 {
        return Err("responder signature must be 64 bytes".into());
    }
    let mut resp_sig_arr = [0u8; 64];
    resp_sig_arr.copy_from_slice(&resp_sig_bytes);
    let resp_sig = Signature::from_bytes(&resp_sig_arr);

    let response = ResponderHello {
        e_pub: resp_e,
        s_pub: resp_s,
        signature: resp_sig,
    };

    // Propagate any CryptoError as String
    let (finish, session_keys) = initiator_finish(&state, &response)
        .map_err(|e| e.to_string())?;

    Ok(HandshakeInitiatorFinishResult {
        s_pub_hex: hex::encode(finish.s_pub.to_bytes()),
        signature_hex: hex::encode(finish.signature.to_bytes()),
        session_key_hex: hex::encode(session_keys.session_key),
    })
}

#[frb]
pub fn client_responder_finish(
    session_id: String,
    initiator_s_pub_hex: String,
    initiator_signature_hex: String,
) -> Result<String, String> {
    let state = get_responder_states()
        .lock()
        .unwrap()
        .remove(&session_id)
        .ok_or_else(|| "handshake session not found".to_string())?;

    let init_s_bytes = hex::decode(&initiator_s_pub_hex).map_err(|e| e.to_string())?;
    if init_s_bytes.len() != 32 {
        return Err("initiator s_pub must be 32 bytes".into());
    }
    let mut init_s_arr = [0u8; 32];
    init_s_arr.copy_from_slice(&init_s_bytes);
    let init_s = VerifyingKey::from_bytes(&init_s_arr).map_err(|e| e.to_string())?;

    let init_sig_bytes = hex::decode(&initiator_signature_hex).map_err(|e| e.to_string())?;
    if init_sig_bytes.len() != 64 {
        return Err("initiator signature must be 64 bytes".into());
    }
    let mut init_sig_arr = [0u8; 64];
    init_sig_arr.copy_from_slice(&init_sig_bytes);
    let init_sig = Signature::from_bytes(&init_sig_arr);

    let finish = InitiatorFinish {
        s_pub: init_s,
        signature: init_sig,
    };

    let session_keys = responder_finish(&state, &finish)
        .map_err(|e| e.to_string())?;

    Ok(hex::encode(session_keys.session_key))
}

use crypto_core::double_ratchet::RatchetState;

static RATCHET_STATES: OnceLock<Mutex<HashMap<String, RatchetState>>> = OnceLock::new();

fn get_ratchet_states() -> &'static Mutex<HashMap<String, RatchetState>> {
    RATCHET_STATES.get_or_init(|| Mutex::new(HashMap::new()))
}

#[frb]
pub fn client_ratchet_init(
    session_id: String,
    session_key_hex: String,
    is_initiator: bool,
) -> Result<(), String> {
    let key_bytes = hex::decode(&session_key_hex).map_err(|e| e.to_string())?;
    if key_bytes.len() != 32 {
        return Err("session key must be 32 bytes".into());
    }
    let mut key_arr = [0u8; 32];
    key_arr.copy_from_slice(&key_bytes);

    let state = RatchetState::from_shared_secret(&key_arr, is_initiator);
    get_ratchet_states().lock().unwrap().insert(session_id, state);
    Ok(())
}

#[frb]
pub fn client_ratchet_encrypt(
    session_id: String,
    plaintext: String,
) -> Result<String, String> {
    let mut guard = get_ratchet_states().lock().unwrap();
    let state = guard.get_mut(&session_id)
        .ok_or_else(|| "ratchet state not found".to_string())?;

    let ciphertext = state.encrypt(plaintext.as_bytes());
    Ok(hex::encode(ciphertext))
}

#[frb]
pub fn client_ratchet_decrypt(
    session_id: String,
    ciphertext_hex: String,
) -> Result<String, String> {
    let mut guard = get_ratchet_states().lock().unwrap();
    let state = guard.get_mut(&session_id)
        .ok_or_else(|| "ratchet state not found".to_string())?;

    let ciphertext = hex::decode(&ciphertext_hex).map_err(|e| e.to_string())?;
    let plaintext_bytes = state.decrypt(&ciphertext)
        .ok_or_else(|| "decryption failed or replay detected".to_string())?;

    String::from_utf8(plaintext_bytes).map_err(|e| e.to_string())
}

#[frb]
pub fn client_generate_zk_proof(secret_hex: String, challenge_hex: String) -> Result<String, String> {
    let secret_bytes = hex::decode(&secret_hex).map_err(|e| e.to_string())?;
    if secret_bytes.len() != 32 {
        return Err("secret must be 32 bytes".into());
    }
    let mut secret_arr = [0u8; 32];
    secret_arr.copy_from_slice(&secret_bytes);

    let challenge_bytes = hex::decode(&challenge_hex).map_err(|e| e.to_string())?;
    let proof = crypto_core::zkp::generate_zk_proof(&secret_arr, &challenge_bytes);
    Ok(hex::encode(proof))
}

#[frb]
pub fn client_verify_zk_proof(public_key_hex: String, challenge_hex: String, proof_hex: String) -> Result<bool, String> {
    let pk_bytes = hex::decode(&public_key_hex).map_err(|e| e.to_string())?;
    if pk_bytes.len() != 32 {
        return Err("public key must be 32 bytes".into());
    }
    let mut pk_arr = [0u8; 32];
    pk_arr.copy_from_slice(&pk_bytes);

    let challenge_bytes = hex::decode(&challenge_hex).map_err(|e| e.to_string())?;

    let proof_bytes = hex::decode(&proof_hex).map_err(|e| e.to_string())?;
    if proof_bytes.len() != 64 {
        return Err("proof must be 64 bytes".into());
    }
    let mut proof_arr = [0u8; 64];
    proof_arr.copy_from_slice(&proof_bytes);

    let result = crypto_core::zkp::verify_zk_proof(&pk_arr, &challenge_bytes, &proof_arr);
    Ok(result)
}

#[frb]
#[derive(Debug, Clone)]
pub struct MlsWelcomeMessageFfi {
    pub group_id_hex: String,
    pub epoch: u64,
    pub encrypted_epoch_secret_hex: String,
    pub members_hex: Vec<String>,
}

#[frb]
#[derive(Debug, Clone)]
pub struct MlsEncryptedMessageFfi {
    pub epoch: u64,
    pub sender_hex: String,
    pub nonce_hex: String,
    pub ciphertext_hex: String,
}

static MLS_SESSIONS: OnceLock<Mutex<HashMap<String, MlsGroupSession>>> = OnceLock::new();

fn get_mls_sessions() -> &'static Mutex<HashMap<String, MlsGroupSession>> {
    MLS_SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

#[frb]
pub fn client_mls_create_group(session_id: String, group_id_hex: String, my_key_hex: String) -> Result<(), String> {
    let group_id_bytes = hex::decode(&group_id_hex).map_err(|e| e.to_string())?;
    if group_id_bytes.len() != 16 {
        return Err("group_id must be 16 bytes (32 hex characters)".into());
    }
    let mut group_id = [0u8; 16];
    group_id.copy_from_slice(&group_id_bytes);

    let my_key_bytes = hex::decode(&my_key_hex).map_err(|e| e.to_string())?;
    if my_key_bytes.len() != 32 {
        return Err("private key must be 32 bytes".into());
    }
    let mut my_key_arr = [0u8; 32];
    my_key_arr.copy_from_slice(&my_key_bytes);
    let my_key = SigningKey::from_bytes(&my_key_arr);

    let session = MlsGroupSession::create_group(group_id, my_key);
    get_mls_sessions().lock().unwrap().insert(session_id, session);
    Ok(())
}

#[frb]
pub fn client_mls_invite_member(session_id: String, new_member_pubkey_hex: String) -> Result<MlsWelcomeMessageFfi, String> {
    let mut guard = get_mls_sessions().lock().unwrap();
    let session = guard.get_mut(&session_id)
        .ok_or_else(|| "MLS session not found".to_string())?;

    let pubkey_bytes = hex::decode(&new_member_pubkey_hex).map_err(|e| e.to_string())?;
    if pubkey_bytes.len() != 32 {
        return Err("new member pubkey must be 32 bytes".into());
    }
    let mut pubkey = [0u8; 32];
    pubkey.copy_from_slice(&pubkey_bytes);

    let welcome = session.invite_member(pubkey).map_err(|e| e.to_string())?;
    Ok(MlsWelcomeMessageFfi {
        group_id_hex: hex::encode(welcome.group_id),
        epoch: welcome.epoch,
        encrypted_epoch_secret_hex: hex::encode(welcome.encrypted_epoch_secret),
        members_hex: welcome.members.iter().map(|m| hex::encode(m)).collect(),
    })
}

#[frb]
pub fn client_mls_join_group(session_id: String, welcome: MlsWelcomeMessageFfi, my_key_hex: String) -> Result<(), String> {
    let group_id_bytes = hex::decode(&welcome.group_id_hex).map_err(|e| e.to_string())?;
    if group_id_bytes.len() != 16 {
        return Err("group_id must be 16 bytes".into());
    }
    let mut group_id = [0u8; 16];
    group_id.copy_from_slice(&group_id_bytes);

    let encrypted_secret = hex::decode(&welcome.encrypted_epoch_secret_hex).map_err(|e| e.to_string())?;

    let mut members = Vec::new();
    for m_hex in welcome.members_hex {
        let m_bytes = hex::decode(&m_hex).map_err(|e| e.to_string())?;
        if m_bytes.len() != 32 {
            return Err("member key must be 32 bytes".into());
        }
        let mut m_arr = [0u8; 32];
        m_arr.copy_from_slice(&m_bytes);
        members.push(m_arr);
    }

    let welcome_struct = WelcomeMessage {
        group_id,
        epoch: welcome.epoch,
        encrypted_epoch_secret: encrypted_secret,
        members,
    };

    let my_key_bytes = hex::decode(&my_key_hex).map_err(|e| e.to_string())?;
    if my_key_bytes.len() != 32 {
        return Err("private key must be 32 bytes".into());
    }
    let mut my_key_arr = [0u8; 32];
    my_key_arr.copy_from_slice(&my_key_bytes);
    let my_key = SigningKey::from_bytes(&my_key_arr);

    let session = MlsGroupSession::join_group(welcome_struct, my_key).map_err(|e| e.to_string())?;
    get_mls_sessions().lock().unwrap().insert(session_id, session);
    Ok(())
}

#[frb]
pub fn client_mls_commit_epoch(session_id: String, entropy_hex: String) -> Result<String, String> {
    let mut guard = get_mls_sessions().lock().unwrap();
    let session = guard.get_mut(&session_id)
        .ok_or_else(|| "MLS session not found".to_string())?;

    let entropy_bytes = hex::decode(&entropy_hex).map_err(|e| e.to_string())?;
    if entropy_bytes.len() != 32 {
        return Err("entropy must be 32 bytes".into());
    }
    let mut entropy = [0u8; 32];
    entropy.copy_from_slice(&entropy_bytes);

    let new_secret = session.commit_epoch(&entropy);
    Ok(hex::encode(new_secret))
}

#[frb]
pub fn client_mls_encrypt_message(session_id: String, plaintext: String) -> Result<MlsEncryptedMessageFfi, String> {
    let guard = get_mls_sessions().lock().unwrap();
    let session = guard.get(&session_id)
        .ok_or_else(|| "MLS session not found".to_string())?;

    let enc = session.encrypt_message(plaintext.as_bytes()).map_err(|e| e.to_string())?;
    Ok(MlsEncryptedMessageFfi {
        epoch: enc.epoch,
        sender_hex: hex::encode(enc.sender),
        nonce_hex: hex::encode(enc.nonce),
        ciphertext_hex: hex::encode(enc.ciphertext),
    })
}

#[frb]
pub fn client_mls_decrypt_message(session_id: String, msg: MlsEncryptedMessageFfi) -> Result<String, String> {
    let guard = get_mls_sessions().lock().unwrap();
    let session = guard.get(&session_id)
        .ok_or_else(|| "MLS session not found".to_string())?;

    let sender_bytes = hex::decode(&msg.sender_hex).map_err(|e| e.to_string())?;
    if sender_bytes.len() != 32 {
        return Err("sender must be 32 bytes".into());
    }
    let mut sender = [0u8; 32];
    sender.copy_from_slice(&sender_bytes);

    let nonce_bytes = hex::decode(&msg.nonce_hex).map_err(|e| e.to_string())?;
    if nonce_bytes.len() != 12 {
        return Err("nonce must be 12 bytes".into());
    }
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&nonce_bytes);

    let ciphertext = hex::decode(&msg.ciphertext_hex).map_err(|e| e.to_string())?;

    let enc_struct = EncryptedGroupMessage {
        epoch: msg.epoch,
        sender,
        nonce,
        ciphertext,
    };

    let plaintext_bytes = session.decrypt_message(&enc_struct).map_err(|e| e.to_string())?;
    String::from_utf8(plaintext_bytes).map_err(|e| e.to_string())
}


