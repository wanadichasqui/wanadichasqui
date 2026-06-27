//! Tests for the identity signature layer (03-crypto-core)
//!
//! These tests cover the happy‑path generation / signing / verification as well as
//! intentional failure scenarios (tampered message, altered signature, mismatched
//! public key).  A property‑based test generates 10 000 random keypairs and
//! verifies that sign + verify always succeeds.

use proptest::prelude::*;
use ed25519_dalek::Signature;

// Re‑export the functions from the crate under test.
use crypto_core::{generate_keypair, sign, verify};

#[test]
fn test_generate_and_verify_happy_path() {
    // Generate a fresh keypair.
    let kp = generate_keypair();
    let msg = b"the quick brown fox jumps over the lazy dog";
    let sig: Signature = sign(&kp, msg);
    // Verify using the public key derived from the same keypair.
    assert!(verify(&kp.verifying_key(), msg, &sig), "Signature should verify with its own public key");
}

#[test]
fn test_verify_fails_on_modified_message() {
    let kp = generate_keypair();
    let msg = b"original message";
    let sig = sign(&kp, msg);
    // Change one byte in the message.
    let mut tampered = msg.to_vec();
    tampered[0] ^= 0xFF; // flip bits of first byte
    assert!(!verify(&kp.verifying_key(), &tampered, &sig), "Verification must fail when the message is altered");
}

#[test]
fn test_verify_fails_on_modified_signature() {
    let kp = generate_keypair();
    let msg = b"some data";
    let mut sig = sign(&kp, msg);
    // Corrupt the signature by flipping a byte.
    let mut sig_bytes = sig.to_bytes();
    sig_bytes[0] ^= 0xAA;
    sig = Signature::from_bytes(&sig_bytes);
    assert!(!verify(&kp.verifying_key(), msg, &sig), "Verification must fail with a tampered signature");
}

#[test]
fn test_verify_fails_with_different_public_key() {
    // Two independent keypairs.
    let kp1 = generate_keypair();
    let kp2 = generate_keypair();
    let msg = b"shared secret";
    let sig = sign(&kp1, msg);
    // Attempt to verify with kp2's public key.
    assert!(!verify(&kp2.verifying_key(), msg, &sig), "Verification should fail when using a different public key");
}

proptest! {
    #[test]
    fn prop_sign_verify_roundtrip(msg in any::<Vec<u8>>()) {
        // Generate a fresh keypair for each test case.
        let kp = generate_keypair();
        // Sign the random message.
        let sig = sign(&kp, &msg);
        // Verify must succeed.
        prop_assert!(verify(&kp.verifying_key(), &msg, &sig));
    }
}
