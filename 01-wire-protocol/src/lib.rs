//! Wire protocol library – re‑exports packet definitions.

mod packet;
pub use packet::*;

pub mod ble_beacon;

#[cfg(test)]
mod tests;
