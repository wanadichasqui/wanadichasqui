//! Wrappers de claves Ed25519 usando `ed25519-dalek`.
use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};
use rand::rngs::OsRng;

/// Genera un par de claves aleatorias.
pub fn generate_keypair() -> SigningKey {
    SigningKey::generate(&mut OsRng)
}

/// Firma `msg` con la clave secreta del `signing_key`.
pub fn sign(signing_key: &SigningKey, msg: &[u8]) -> Signature {
    signing_key.sign(msg)
}

/// Verifica una firma con la clave pública.
pub fn verify(verifying_key: &VerifyingKey, msg: &[u8], sig: &Signature) -> bool {
    verifying_key.verify(msg, sig).is_ok()
}
