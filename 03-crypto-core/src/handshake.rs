//! Handshake Noise XX adaptado con identidades Ed25519.
//!
//! Flujo en tres pasos:
//!   A -> B: InitiatorHello { e_pub }
//!   B -> A: ResponderHello { e_pub, s_pub, signature }
//!   A -> B: InitiatorFinish { s_pub, signature }
//!
//! Ambos derivan la misma clave de sesión de 32 bytes al finalizar.

use crate::key_agreement::{diffie_hellman, derive_keys, CryptoError};
use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};
use rand::rngs::OsRng;
use x25519_dalek::{PublicKey as X25519PublicKey, StaticSecret as X25519SecretKey};

#[derive(Clone, Copy)]
pub struct InitiatorHello {
    pub e_pub: X25519PublicKey,
}

pub struct InitiatorState {
    e_secret: X25519SecretKey,
    signing_key: SigningKey,
    hello: InitiatorHello,
}

pub struct ResponderHello {
    pub e_pub: X25519PublicKey,
    pub s_pub: VerifyingKey,
    pub signature: Signature,
}

pub struct ResponderState {
    shared_secret: [u8; 32],
    initiator_e_pub: X25519PublicKey,
    responder_e_pub: X25519PublicKey,
}

pub struct InitiatorFinish {
    pub s_pub: VerifyingKey,
    pub signature: Signature,
}

pub struct SessionKeys {
    pub session_key: [u8; 32],
}

pub fn initiator_hello(id: &SigningKey) -> (InitiatorState, InitiatorHello) {
    let e_secret = X25519SecretKey::random_from_rng(&mut OsRng);
    let e_pub = X25519PublicKey::from(&e_secret);
    let hello = InitiatorHello { e_pub };
    let state = InitiatorState {
        e_secret,
        signing_key: id.clone(),
        hello,
    };
    (state, hello)
}

pub fn responder_hello(
    id: &SigningKey,
    initiator_hello: &InitiatorHello,
) -> Result<(ResponderState, ResponderHello), CryptoError> {
    let e_secret = X25519SecretKey::random_from_rng(&mut OsRng);
    let e_pub = X25519PublicKey::from(&e_secret);
    let shared = diffie_hellman(&e_secret, &initiator_hello.e_pub)?;
    let mut msg = Vec::new();
    msg.extend_from_slice(e_pub.as_bytes());
    msg.extend_from_slice(initiator_hello.e_pub.as_bytes());
    let signature = id.sign(&msg);
    let s_pub = id.verifying_key();
    let response = ResponderHello { e_pub, s_pub, signature };
    let state = ResponderState {
        shared_secret: shared,
        initiator_e_pub: initiator_hello.e_pub,
        responder_e_pub: e_pub,
    };
    Ok((state, response))
}

pub fn initiator_finish(
    state: &InitiatorState,
    response: &ResponderHello,
) -> Result<(InitiatorFinish, SessionKeys), CryptoError> {
    // Verify responder's signature
    let mut verify_msg = Vec::new();
    verify_msg.extend_from_slice(response.e_pub.as_bytes());
    verify_msg.extend_from_slice(state.hello.e_pub.as_bytes());
    response
        .s_pub
        .verify(&verify_msg, &response.signature)
        .map_err(|e| CryptoError::HkdfExpandError(format!("Signature verification failed: {:?}", e)))?;
    // Compute shared secret
    let shared = diffie_hellman(&state.e_secret, &response.e_pub)?;
    // Build our finish message and sign it
    let mut finish_msg = Vec::new();
    finish_msg.extend_from_slice(state.hello.e_pub.as_bytes());
    finish_msg.extend_from_slice(response.e_pub.as_bytes());
    let signature = state.signing_key.sign(&finish_msg);
    let s_pub = state.signing_key.verifying_key();
    let finish = InitiatorFinish { s_pub, signature };
    let session_key = derive_keys(&shared, b"wanadi-chasqui-handshake-xx")?;
    Ok((finish, SessionKeys { session_key }))
}

pub fn responder_finish(
    state: &ResponderState,
    finish: &InitiatorFinish,
) -> Result<SessionKeys, CryptoError> {
    use ed25519_dalek::Verifier;

    // Verify initiator's signature
    let mut verify_msg = Vec::new();
    verify_msg.extend_from_slice(state.initiator_e_pub.as_bytes());
    verify_msg.extend_from_slice(state.responder_e_pub.as_bytes());

    finish
        .s_pub
        .verify(&verify_msg, &finish.signature)
        .map_err(|e| CryptoError::HkdfExpandError(format!("Initiator signature verification failed: {:?}", e)))?;

    let session_key = derive_keys(&state.shared_secret, b"wanadi-chasqui-handshake-xx")?;
    Ok(SessionKeys { session_key })
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::SigningKey;
    use rand::rngs::OsRng;

    #[test]
    fn test_complete_handshake() -> Result<(), CryptoError> {
        let id_a = SigningKey::generate(&mut OsRng);
        let id_b = SigningKey::generate(&mut OsRng);
        let (state_a, hello) = initiator_hello(&id_a);
        let (state_b, response) = responder_hello(&id_b, &hello)?;
        let (finish, keys_a) = initiator_finish(&state_a, &response)?;
        let keys_b = responder_finish(&state_b, &finish)?;
        assert_eq!(keys_a.session_key, keys_b.session_key);
        Ok(())
    }

    #[test]
    fn test_responder_signature_tampered() {
        let id_a = SigningKey::generate(&mut OsRng);
        let id_b = SigningKey::generate(&mut OsRng);
        let (state_a, hello) = initiator_hello(&id_a);
        let (mut _state_b, mut response) = responder_hello(&id_b, &hello).unwrap();
        let mut sig_bytes = response.signature.to_bytes();
        sig_bytes[0] ^= 0xFF;
        response.signature = Signature::from_bytes(&sig_bytes);
        let result = std::panic::catch_unwind(move || {
            initiator_finish(&state_a, &response).unwrap();
        });
        assert!(result.is_err(), "Responder signature tampering must fail");
    }

    #[test]
    fn test_initiator_signature_tampered() {
        let id_a = SigningKey::generate(&mut OsRng);
        let id_b = SigningKey::generate(&mut OsRng);
        let (state_a, hello) = initiator_hello(&id_a);
        let (state_b, response) = responder_hello(&id_b, &hello).unwrap();
        let (mut finish, _) = initiator_finish(&state_a, &response).unwrap();
        let mut sig_bytes = finish.signature.to_bytes();
        sig_bytes[0] ^= 0xFF;
        finish.signature = Signature::from_bytes(&sig_bytes);
        let result = std::panic::catch_unwind(move || {
            responder_finish(&state_b, &finish).unwrap();
        });
        assert!(result.is_err(), "Initiator signature tampering must fail");
    }
}
