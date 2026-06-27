//! Módulo de Pruebas de Conocimiento Cero (ZKP) para Wanadi Chasqui.
//! Implementa una prueba Schnorr de conocimiento de clave privada (preimagen)
//! mediante el esquema Fiat-Shamir sobre Ed25519.

use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};

/// Genera una prueba ZK de que se conoce el secreto `secret` (semilla de clave privada)
/// asociado a la clave pública correspondiente, firmando un `challenge` específico.
/// La prueba resultante es una firma criptográfica de 64 bytes.
pub fn generate_zk_proof(secret: &[u8; 32], challenge: &[u8]) -> [u8; 64] {
    let signing_key = SigningKey::from_bytes(secret);
    let signature = signing_key.sign(challenge);
    signature.to_bytes()
}

/// Verifica una prueba ZK. Toma la clave pública `public_key` (32 bytes), el `challenge` original,
/// y la prueba de 64 bytes. Devuelve true si la prueba es válida.
pub fn verify_zk_proof(public_key: &[u8; 32], challenge: &[u8], proof: &[u8; 64]) -> bool {
    let Ok(verifying_key) = VerifyingKey::from_bytes(public_key) else {
        return false;
    };
    let signature = Signature::from_bytes(proof);
    verifying_key.verify(challenge, &signature).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_zk_proof_flow() {
        let secret = [7u8; 32]; // Secreto de la invitación
        let challenge = b"session_challenge_xyz_123";

        // 1. Prover genera la clave pública de la invitación para compartirla/publicarla
        let pub_key = SigningKey::from_bytes(&secret).verifying_key().to_bytes();

        // 2. Prover demuestra posesión del secreto sin revelarlo
        let proof = generate_zk_proof(&secret, challenge);

        // 3. Verifier valida la prueba
        assert!(verify_zk_proof(&pub_key, challenge, &proof));

        // 4. Verificaciones con datos corruptos fallan
        let bad_challenge = b"session_challenge_xyz_124";
        assert!(!verify_zk_proof(&pub_key, bad_challenge, &proof));
    }
}
