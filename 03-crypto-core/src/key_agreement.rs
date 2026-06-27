//! X25519 key agreement and HKDF key derivation utilities.
//!
//! This module provides two public functions:
//!
//! 1. `diffie_hellman` – Performs an X25519 Diffie‑Hellman exchange.
//! 2. `derive_keys` – Derives a 32‑byte symmetric key from the shared secret
//!    using HKDF‑SHA256 with a caller‑supplied `info` slice.
//!
//! The API is deliberately tiny because higher‑level protocols (handshake,
//! double‑ratchet, etc.) will build on top of it.
//!
//! # Usage example
//! ```rust
//! use crypto_core::{diffie_hellman, derive_keys, CryptoError};
//! use x25519_dalek::{StaticSecret, PublicKey};
//!
//! // Party A generates a static secret and corresponding public key.
//! let secret_a = StaticSecret::random_from_rng(&mut rand::rngs::OsRng);
//! let pub_a = PublicKey::from(&secret_a);
//!
//! // Party B does the same.
//! let secret_b = StaticSecret::random_from_rng(&mut rand::rngs::OsRng);
//! let pub_b = PublicKey::from(&secret_b);
//!
//! // Perform DH – the result is the same for both parties.
//! let shared_a = diffie_hellman(&secret_a, &pub_b)?;
//! let shared_b = diffie_hellman(&secret_b, &pub_a)?;
//! assert_eq!(shared_a, shared_b);
//!
//! // Derive a symmetric key for encryption.
//! let key = derive_keys(&shared_a, b"handshake-key")?;
//! assert_eq!(key.len(), 32);
//! # Ok::<(), CryptoError>(())
//! ```
//!
//! # Crate dependencies
//! //! - `x25519-dalek = { version = "2.0.1", features = ["static_secrets"] }`
//! //! - `hkdf = "0.12.1"`
//! //! - `sha2 = "0.10"` (already a dependency of `ed25519-dalek`).
//!
//! The implementation follows the standard RFC 7748 X25519 operation and RFC 5869 HKDF construction.

use x25519_dalek::{PublicKey, StaticSecret};
use hkdf::Hkdf;
use sha2::Sha256;

/// Errors that can be returned by this module.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum CryptoError {
    /// Failure in the HKDF expand step.
    #[error("HKDF expand failed: {0}")]
    HkdfExpandError(String),
}

/// Perform an X25519 Diffie‑Hellman key exchange.
///
/// Given our own static secret and the peer's public key, returns the 32‑byte
/// shared secret as a fixed‑size array.
///
/// This operation never fails under normal circumstances, so we return `Ok`.
pub fn diffie_hellman(secret: &StaticSecret, peer: &PublicKey) -> Result<[u8; 32], CryptoError> {
    let shared = secret.diffie_hellman(peer);
    Ok(*shared.as_bytes())
}

/// Derive a 32‑byte symmetric key from a shared secret using HKDF‑SHA256.
///
/// The caller supplies an `info` slice so the same function can be reused for
/// different purposes (handshake, ratchet, backup, …). The output is always 32
/// bytes (256 bits), suitable for AEAD schemes such as XChaCha20‑Poly1305.
pub fn derive_keys(shared_secret: &[u8], info: &[u8]) -> Result<[u8; 32], CryptoError> {
    let hk = Hkdf::<Sha256>::new(None, shared_secret);
    let mut okm = [0u8; 32];
    hk.expand(info, &mut okm)
        .map_err(|e| CryptoError::HkdfExpandError(format!("{:?}", e)))?;
    Ok(okm)
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use rand::rngs::OsRng;
    use x25519_dalek::{StaticSecret, PublicKey};

    #[test]
    fn test_diffie_hellman_symmetry() -> Result<(), CryptoError> {
        let secret_a = StaticSecret::random_from_rng(&mut OsRng);
        let pub_a = PublicKey::from(&secret_a);
        let secret_b = StaticSecret::random_from_rng(&mut OsRng);
        let pub_b = PublicKey::from(&secret_b);
        let secret1 = diffie_hellman(&secret_a, &pub_b)?;
        let secret2 = diffie_hellman(&secret_b, &pub_a)?;
        assert_eq!(secret1, secret2);
        Ok(())
    }

    #[test]
    fn test_derive_keys_deterministic() -> Result<(), CryptoError> {
        let secret = [0xAAu8; 32];
        let info = b"test-info";
        let key1 = derive_keys(&secret, info)?;
        let key2 = derive_keys(&secret, info)?;
        assert_eq!(key1, key2);
        Ok(())
    }

    proptest! {
        #[test]
        fn prop_dh_symmetry(_a in any::<[u8; 32]>(), _b in any::<[u8; 32]>()) {
            // Generate secrets via API to guarantee valid scalars.
            let secret_a = StaticSecret::random_from_rng(&mut OsRng);
            let secret_b = StaticSecret::random_from_rng(&mut OsRng);
            let pub_a = PublicKey::from(&secret_a);
            let pub_b = PublicKey::from(&secret_b);
            let shared1 = diffie_hellman(&secret_a, &pub_b).unwrap();
            let shared2 = diffie_hellman(&secret_b, &pub_a).unwrap();
            prop_assert_eq!(shared1, shared2);
        }
    }
}
