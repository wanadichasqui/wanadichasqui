// Copyright (C) 2026 Juan Carlos Diaz Parisca / Wanadi Tactical
//
// This file is part of Wanadi Chasqui.
//
// Wanadi Chasqui is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License version 3
// as published by the Free Software Foundation.
//
// Wanadi Chasqui is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See <https://www.gnu.org/licenses/> for more details.

//! FFI surface (flutter_rust_bridge) for the Flutter client.
//!
//! Scope A: real Ed25519 identity derived from a recovery mnemonic, replacing
//! the placeholder XOR "crypto" that lived in Dart. The public key is the
//! Ed25519 curve point of the private scalar — it is NOT invertible to the
//! private key (unlike the old `pub = priv XOR 0xAA`).

use flutter_rust_bridge::frb;
use ed25519_dalek::SigningKey;

use crate::key_agreement::derive_keys;

/// Domain separation for identity key derivation. Changing this changes every
/// derived identity, so it is versioned and must stay stable.
const IDENTITY_INFO: &[u8] = b"wanadi-chasqui-identity-v1";

/// A device identity: 32-byte Ed25519 private/public keys, hex-encoded.
#[frb]
#[derive(Debug, Clone)]
pub struct Identity {
    pub private_key_hex: String,
    pub public_key_hex: String,
}

/// Derive a real Ed25519 identity from a recovery mnemonic.
///
/// Deterministic: the same mnemonic always yields the same keypair, so the
/// mnemonic is a true backup/restore phrase.
#[frb]
pub fn identity_from_mnemonic(mnemonic: String) -> Result<Identity, String> {
    let trimmed = mnemonic.trim();
    if trimmed.is_empty() {
        return Err("mnemonic vacío".to_string());
    }
    let seed = derive_keys(trimmed.as_bytes(), IDENTITY_INFO)
        .map_err(|e| format!("derivación de clave falló: {:?}", e))?;
    let sk = SigningKey::from_bytes(&seed);
    let vk = sk.verifying_key();
    Ok(Identity {
        private_key_hex: to_hex(&sk.to_bytes()),
        public_key_hex: to_hex(vk.as_bytes()),
    })
}

/// Recompute the Ed25519 public key from a hex private key (32 bytes).
#[frb]
pub fn public_from_private(private_key_hex: String) -> Result<String, String> {
    let bytes = from_hex(&private_key_hex)?;
    if bytes.len() != 32 {
        return Err("la clave privada debe ser de 32 bytes".to_string());
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    let sk = SigningKey::from_bytes(&arr);
    Ok(to_hex(sk.verifying_key().as_bytes()))
}

/// Sign a UTF-8 message with a hex private key; returns the hex signature.
#[frb]
pub fn sign_message(private_key_hex: String, message: String) -> Result<String, String> {
    use ed25519_dalek::Signer;
    let bytes = from_hex(&private_key_hex)?;
    if bytes.len() != 32 {
        return Err("la clave privada debe ser de 32 bytes".to_string());
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    let sk = SigningKey::from_bytes(&arr);
    let sig = sk.sign(message.as_bytes());
    Ok(to_hex(&sig.to_bytes()))
}

// ── hex helpers (sin dependencia externa) ──────────────────────────

fn to_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

fn from_hex(s: &str) -> Result<Vec<u8>, String> {
    let s = s.trim();
    if s.len() % 2 != 0 {
        return Err("hex de longitud impar".to_string());
    }
    let mut out = Vec::with_capacity(s.len() / 2);
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let hi = hex_val(bytes[i])?;
        let lo = hex_val(bytes[i + 1])?;
        out.push((hi << 4) | lo);
        i += 2;
    }
    Ok(out)
}

fn hex_val(c: u8) -> Result<u8, String> {
    match c {
        b'0'..=b'9' => Ok(c - b'0'),
        b'a'..=b'f' => Ok(c - b'a' + 10),
        b'A'..=b'F' => Ok(c - b'A' + 10),
        _ => Err("carácter hex inválido".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_is_deterministic_and_real() {
        let a = identity_from_mnemonic("uno dos tres cuatro".to_string()).unwrap();
        let b = identity_from_mnemonic("uno dos tres cuatro".to_string()).unwrap();
        assert_eq!(a.private_key_hex, b.private_key_hex);
        assert_eq!(a.public_key_hex, b.public_key_hex);

        // La pública NO es la privada XOR 0xAA (el bug viejo).
        assert_ne!(a.private_key_hex, a.public_key_hex);
        let priv_bytes = from_hex(&a.private_key_hex).unwrap();
        let pub_bytes = from_hex(&a.public_key_hex).unwrap();
        let xor: Vec<u8> = priv_bytes.iter().map(|b| b ^ 0xAA).collect();
        assert_ne!(xor, pub_bytes, "la pública no debe ser invertible desde la privada");
    }

    #[test]
    fn different_mnemonics_differ() {
        let a = identity_from_mnemonic("frase uno".to_string()).unwrap();
        let b = identity_from_mnemonic("frase dos".to_string()).unwrap();
        assert_ne!(a.public_key_hex, b.public_key_hex);
    }

    #[test]
    fn public_from_private_matches() {
        let id = identity_from_mnemonic("recuperación seto vela".to_string()).unwrap();
        let derived = public_from_private(id.private_key_hex.clone()).unwrap();
        assert_eq!(derived, id.public_key_hex);
    }

    #[test]
    fn empty_mnemonic_rejected() {
        assert!(identity_from_mnemonic("   ".to_string()).is_err());
    }
}
