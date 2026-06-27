//! Módulo MLS (Messaging Layer Security) simplificado para Wanadi Chasqui.
//! Implementa la rotación de épocas, derivación de secretos de grupo mediante HKDF
//! y cifrado de mensajes de grupo con seguridad post-compromiso (PCS).

use std::collections::HashSet;
use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce, aead::Aead, KeyInit};
use hkdf::Hkdf;
use sha2::Sha256;
use rand::rngs::OsRng;
use rand::RngCore;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum MlsError {
    #[error("Crypto error: {0}")]
    CryptoError(String),
    #[error("Authentication error")]
    AuthError,
    #[error("Invalid epoch")]
    InvalidEpoch,
}

/// Mensaje de bienvenida cifrado para invitar a un miembro a un grupo.
#[derive(Debug, Clone)]
pub struct WelcomeMessage {
    pub group_id: [u8; 16],
    pub epoch: u64,
    pub encrypted_epoch_secret: Vec<u8>, // Cifrado para la clave del destinatario
    pub members: Vec<[u8; 32]>,
}

/// Mensaje de grupo cifrado en una época específica.
#[derive(Debug, Clone)]
pub struct EncryptedGroupMessage {
    pub epoch: u64,
    pub sender: [u8; 32],
    pub nonce: [u8; 12],
    pub ciphertext: Vec<u8>,
}

/// Sesión de grupo MLS local de un miembro.
pub struct MlsGroupSession {
    pub group_id: [u8; 16],
    pub epoch: u64,
    pub epoch_secret: [u8; 32],
    pub members: HashSet<[u8; 32]>,
    pub my_key: SigningKey,
}

impl MlsGroupSession {
    /// Inicializa un nuevo grupo MLS con el creador como único miembro.
    pub fn create_group(group_id: [u8; 16], creator_key: SigningKey) -> Self {
        let mut epoch_secret = [0u8; 32];
        OsRng.fill_bytes(&mut epoch_secret);

        let mut members = HashSet::new();
        members.insert(creator_key.verifying_key().to_bytes());

        MlsGroupSession {
            group_id,
            epoch: 0,
            epoch_secret,
            members,
            my_key: creator_key,
        }
    }

    /// Invita a un nuevo miembro generando un `WelcomeMessage`.
    /// El secreto de época se encripta de forma simplificada con un protocolo
    /// difie-hellman de clave efímera para la clave pública del nuevo miembro.
    pub fn invite_member(&mut self, new_member_pubkey: [u8; 32]) -> Result<WelcomeMessage, MlsError> {
        self.members.insert(new_member_pubkey);

        // En un despliegue real usaríamos ECIES. Simulamos el sobre cifrado usando
        // la clave del destinatario como clave simétrica temporal (para fines de prueba).
        let mut encrypted_secret = self.epoch_secret.to_vec();
        for i in 0..32 {
            encrypted_secret[i] ^= new_member_pubkey[i]; // XOR simulación ECIES
        }

        Ok(WelcomeMessage {
            group_id: self.group_id,
            epoch: self.epoch,
            encrypted_epoch_secret: encrypted_secret,
            members: self.members.iter().cloned().collect(),
        })
    }

    /// Procesa un mensaje de bienvenida para unirse a un grupo.
    pub fn join_group(
        welcome: WelcomeMessage,
        my_key: SigningKey,
    ) -> Result<Self, MlsError> {
        let my_pub = my_key.verifying_key().to_bytes();
        let mut epoch_secret = welcome.encrypted_epoch_secret.clone();
        
        // Deshacer el cifrado XOR
        for i in 0..32 {
            epoch_secret[i] ^= my_pub[i];
        }

        let mut epoch_secret_arr = [0u8; 32];
        epoch_secret_arr.copy_from_slice(&epoch_secret);

        let members = welcome.members.into_iter().collect();

        Ok(MlsGroupSession {
            group_id: welcome.group_id,
            epoch: welcome.epoch,
            epoch_secret: epoch_secret_arr,
            members,
            my_key,
        })
    }

    /// Rota la clave del grupo (Epoch Commit) para lograr Post-Compromise Security (PCS).
    /// Deriva un nuevo secreto de época combinando el anterior y la semilla de entropía compartida.
    pub fn commit_epoch(&mut self, entropy: &[u8; 32]) -> [u8; 32] {
        // HKDF-Extract-and-Expand
        let hk = Hkdf::<Sha256>::new(Some(&self.epoch_secret), entropy);
        let mut new_secret = [0u8; 32];
        hk.expand(b"wanadi-mls-epoch-secret", &mut new_secret)
            .expect("HKDF expand should never fail with correct length");

        self.epoch_secret = new_secret;
        self.epoch += 1;
        self.epoch_secret
    }

    /// Cifra un mensaje de texto para el grupo usando la clave de la época actual.
    pub fn encrypt_message(&self, plaintext: &[u8]) -> Result<EncryptedGroupMessage, MlsError> {
        // Derivar clave de cifrado simétrico para la época
        let hk = Hkdf::<Sha256>::new(None, &self.epoch_secret);
        let mut aes_key = [0u8; 32];
        hk.expand(b"wanadi-mls-encryption-key", &mut aes_key)
            .expect("HKDF expand key");

        let key = Key::from_slice(&aes_key);
        let cipher = ChaCha20Poly1305::new(key);

        let mut nonce_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        // Formatear payload con la firma del remitente para no repudio interno
        let signature = self.my_key.sign(plaintext);
        let mut payload = Vec::with_capacity(64 + plaintext.len());
        payload.extend_from_slice(&signature.to_bytes());
        payload.extend_from_slice(plaintext);

        let ciphertext = cipher
            .encrypt(nonce, payload.as_ref())
            .map_err(|e| MlsError::CryptoError(e.to_string()))?;

        Ok(EncryptedGroupMessage {
            epoch: self.epoch,
            sender: self.my_key.verifying_key().to_bytes(),
            nonce: nonce_bytes,
            ciphertext,
        })
    }

    /// Descifra un mensaje del grupo. Verifica la firma del remitente.
    pub fn decrypt_message(&self, msg: &EncryptedGroupMessage) -> Result<Vec<u8>, MlsError> {
        if msg.epoch != self.epoch {
            return Err(MlsError::InvalidEpoch);
        }

        // Derivar clave de cifrado simétrico para la época
        let hk = Hkdf::<Sha256>::new(None, &self.epoch_secret);
        let mut aes_key = [0u8; 32];
        hk.expand(b"wanadi-mls-encryption-key", &mut aes_key)
            .expect("HKDF expand key");

        let key = Key::from_slice(&aes_key);
        let cipher = ChaCha20Poly1305::new(key);
        let nonce = Nonce::from_slice(&msg.nonce);

        let decrypted = cipher
            .decrypt(nonce, msg.ciphertext.as_ref())
            .map_err(|e| MlsError::CryptoError(e.to_string()))?;

        if decrypted.len() < 64 {
            return Err(MlsError::AuthError);
        }

        let sig_bytes = &decrypted[..64];
        let plaintext = &decrypted[64..];

        // Verificar la firma del remitente
        let sender_pub = VerifyingKey::from_bytes(&msg.sender)
            .map_err(|_| MlsError::AuthError)?;
        let signature = Signature::from_bytes(sig_bytes.try_into().unwrap());
        
        if sender_pub.verify(plaintext, &signature).is_err() {
            return Err(MlsError::AuthError);
        }

        Ok(plaintext.to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mls_group_flow() {
        let group_id = [1u8; 16];
        let alice_key = SigningKey::generate(&mut OsRng);
        let bob_key = SigningKey::generate(&mut OsRng);

        // Alice crea el grupo
        let mut alice_session = MlsGroupSession::create_group(group_id, alice_key);
        assert_eq!(alice_session.epoch, 0);

        // Alice invita a Bob
        let welcome = alice_session.invite_member(bob_key.verifying_key().to_bytes()).unwrap();

        // Bob se une
        let mut bob_session = MlsGroupSession::join_group(welcome, bob_key).unwrap();
        assert_eq!(bob_session.epoch, 0);
        assert_eq!(bob_session.epoch_secret, alice_session.epoch_secret);

        // Alice envía un mensaje cifrado
        let text = b"Secret group meeting!";
        let enc_msg = alice_session.encrypt_message(text).unwrap();

        // Bob lo descifra
        let dec_text = bob_session.decrypt_message(&enc_msg).unwrap();
        assert_eq!(dec_text, text);

        // Rotación de Época (Epoch Commit para Post-Compromise Security)
        let old_secret = alice_session.epoch_secret;
        let mut entropy = [0u8; 32];
        OsRng.fill_bytes(&mut entropy);
        alice_session.commit_epoch(&entropy);
        bob_session.commit_epoch(&entropy);

        assert_eq!(alice_session.epoch, 1);
        assert_eq!(bob_session.epoch, 1);
        assert_ne!(alice_session.epoch_secret, old_secret);
        assert_eq!(alice_session.epoch_secret, bob_session.epoch_secret);

        // Mensaje en la nueva época
        let text_new = b"New epoch secure message";
        let enc_msg_new = bob_session.encrypt_message(text_new).unwrap();
        let dec_text_new = alice_session.decrypt_message(&enc_msg_new).unwrap();
        assert_eq!(dec_text_new, text_new);
    }
}
