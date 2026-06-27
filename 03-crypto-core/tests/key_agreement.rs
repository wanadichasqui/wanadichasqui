use crypto_core::{diffie_hellman, derive_keys};
use proptest::prelude::*;
use rand::rngs::OsRng;
use rand::SeedableRng;
use x25519_dalek::{PublicKey, StaticSecret};

#[test]
fn test_diffie_hellman_symmetry() {
    let alice = StaticSecret::random_from_rng(&mut OsRng);
    let alice_pub = PublicKey::from(&alice);

    let bob = StaticSecret::random_from_rng(&mut OsRng);
    let bob_pub = PublicKey::from(&bob);

    let s1 = diffie_hellman(&alice, &bob_pub);
    let s2 = diffie_hellman(&bob, &alice_pub);
    assert_eq!(s1, s2, "Shared secrets must match");
}

#[test]
fn test_derive_keys_determinism() {
    let secret = [42u8; 32];
    let info = b"test info";
    let k1 = derive_keys(&secret, info);
    let k2 = derive_keys(&secret, info);
    assert_eq!(k1, k2);
}

proptest! {
    #[test]
    fn prop_diffie_hellman_symmetry(seed in any::<u64>()) {
        let mut rng = rand::rngs::StdRng::seed_from_u64(seed);

        let alice = StaticSecret::random_from_rng(&mut rng);
        let alice_pub = PublicKey::from(&alice);

        let bob = StaticSecret::random_from_rng(&mut rng);
        let bob_pub = PublicKey::from(&bob);

        let s1 = diffie_hellman(&alice, &bob_pub);
        let s2 = diffie_hellman(&bob, &alice_pub);
        prop_assert_eq!(s1, s2);
    }
}
