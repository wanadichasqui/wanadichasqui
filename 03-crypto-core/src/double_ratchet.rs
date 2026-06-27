//! Double Ratchet (simétrico) – forward secrecy por cadena de claves con cifrado autenticado ChaCha20-Poly1305.
use hkdf::Hkdf;
use sha2::Sha256;
use std::collections::HashSet;
use chacha20poly1305::{ChaCha20Poly1305, aead::{Aead, KeyInit, generic_array::GenericArray}};
use rand::RngCore;

pub struct RatchetState {
    send_chain: [u8; 32],
    recv_chain: [u8; 32],
    send_n:     u32,
    recv_n:     u32,
    seen:       HashSet<u32>,
}

fn hkdf32(prk: &[u8;32], info: &[u8], out: &mut [u8;32]) {
    Hkdf::<Sha256>::new(Some(prk), info).expand(b"", out).unwrap();
}

fn msg_key(ck: &[u8;32], n: u32) -> [u8;32] {
    let mut mk = [0u8;32];
    hkdf32(ck, &n.to_le_bytes(), &mut mk);
    mk
}

fn advance(ck: &[u8;32]) -> [u8;32] {
    let mut next = [0u8;32];
    hkdf32(ck, b"advance", &mut next);
    next
}

impl RatchetState {
    pub fn from_shared_secret(ss: &[u8;32], is_initiator: bool) -> Self {
        let mut chain_a2b = [0u8;32];
        hkdf32(ss, b"chain-a2b", &mut chain_a2b);
        let mut chain_b2a = [0u8;32];
        hkdf32(ss, b"chain-b2a", &mut chain_b2a);

        let (send_chain, recv_chain) = if is_initiator {
            (chain_a2b, chain_b2a)
        } else {
            (chain_b2a, chain_a2b)
        };

        Self {
            send_chain,
            recv_chain,
            send_n: 0,
            recv_n: 0,
            seen:   HashSet::new(),
        }
    }

    pub fn encrypt(&mut self, pt: &[u8]) -> Vec<u8> {
        let mk = msg_key(&self.send_chain, self.send_n);
        let n = self.send_n;
        self.send_chain = advance(&self.send_chain);
        self.send_n += 1;

        let cipher = ChaCha20Poly1305::new(GenericArray::from_slice(&mk));
        let mut nonce = [0u8; 12];
        rand::thread_rng().fill_bytes(&mut nonce);

        let ct = cipher.encrypt(GenericArray::from_slice(&nonce), pt)
            .expect("Encryption failed");

        let mut msg = Vec::with_capacity(4 + 12 + ct.len());
        msg.extend(&n.to_le_bytes());
        msg.extend(&nonce);
        msg.extend(&ct);
        msg
    }

    pub fn decrypt(&mut self, msg: &[u8]) -> Option<Vec<u8>> {
        if msg.len() < 4 + 12 { return None; }
        let mn = u32::from_le_bytes(msg[..4].try_into().ok()?);
        let nonce = &msg[4..16];
        let ct = &msg[16..];

        if self.seen.contains(&mn) { return None; }
        self.seen.insert(mn);

        if mn != self.recv_n { return None; }

        let mk = msg_key(&self.recv_chain, mn);
        self.recv_chain = advance(&self.recv_chain);
        self.recv_n += 1;

        let cipher = ChaCha20Poly1305::new(GenericArray::from_slice(&mk));
        cipher.decrypt(GenericArray::from_slice(nonce), ct).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt() {
        let ss = [42u8;32];
        let mut alice = RatchetState::from_shared_secret(&ss, true);
        let mut bob   = RatchetState::from_shared_secret(&ss, false);

        let m1 = alice.encrypt(b"Hola");
        assert_eq!(bob.decrypt(&m1).unwrap(), b"Hola");

        let m2 = bob.encrypt(b"Chasqui");
        assert_eq!(alice.decrypt(&m2).unwrap(), b"Chasqui");
    }

    #[test]
    fn test_forward_secrecy() {
        let ss = [42u8;32];
        let mut alice = RatchetState::from_shared_secret(&ss, true);
        let mut bob   = RatchetState::from_shared_secret(&ss, false);

        let m1 = alice.encrypt(b"uno");
        let m2 = alice.encrypt(b"dos");

        assert_eq!(bob.decrypt(&m1).unwrap(), b"uno");
        assert_eq!(bob.decrypt(&m2).unwrap(), b"dos");

        assert!(bob.decrypt(&m1).is_none(), "replay must fail");
    }
}
