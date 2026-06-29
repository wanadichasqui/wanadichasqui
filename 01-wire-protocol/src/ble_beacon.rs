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

//! Connectionless BLE-advertisement mesh beacons for emergency SOS.
//!
//! BLE advertisement service-data carries only ~20 usable bytes, so a beacon is:
//!   1. encoded to a compact wire form (`encode_sos` / `decode_sos`),
//!   2. fragmented into tiny frames (`fragment_beacon`) advertised one at a time,
//!   3. reassembled by receivers (`BeaconReassembler`) with dedup + TTL pruning.
//!
//! Receivers re-advertise beacons (decrementing `ttl`) so they hop phone-to-phone:
//! that re-advertising loop is the mesh. This module is pure logic — no BLE I/O,
//! no FFI — so it is fully unit-tested below.

use std::collections::HashMap;

/// Priority of an emergency beacon. Higher floods first / lives longer.
pub const PRIORITY_SAFE: u8 = 0; // "estoy a salvo"
pub const PRIORITY_HELP: u8 = 1; // necesito ayuda
pub const PRIORITY_CRITICAL: u8 = 2; // SOS crítico (atrapado / herido)

/// Wire-format version. Bump on any layout change.
const SOS_VERSION: u8 = 1;

/// Max note length in bytes (keeps total payload small enough for few frames).
const MAX_NOTE_LEN: usize = 80;

/// Frame header size: msg_id(4) + total(1) + index(1).
const FRAME_HEADER: usize = 6;

/// A decoded emergency beacon.
#[derive(Debug, Clone, PartialEq)]
pub struct SosBeacon {
    /// Random per-message id, groups fragments and powers dedup.
    pub msg_id: u32,
    /// Hops remaining; decremented on each relay, dropped at 0.
    pub ttl: u8,
    /// One of PRIORITY_*.
    pub priority: u8,
    /// First 4 bytes of the sender identity (short, non-reversible id).
    pub sender_id: [u8; 4],
    /// Latitude  in micro-degrees (degrees * 1e6). i32::MIN = unknown.
    pub lat_micro: i32,
    /// Longitude in micro-degrees (degrees * 1e6). i32::MIN = unknown.
    pub lon_micro: i32,
    /// Short human note (UTF-8, <= MAX_NOTE_LEN bytes).
    pub note: String,
}

impl SosBeacon {
    /// True when no GPS fix was attached.
    pub fn has_location(&self) -> bool {
        self.lat_micro != i32::MIN && self.lon_micro != i32::MIN
    }
}

/// Encode a beacon to its compact wire form.
///
/// Layout (big-endian):
///   ver(1) msg_id(4) ttl(1) priority(1) sender_id(4) lat(4) lon(4) note_len(1) note(..)
pub fn encode_sos(b: &SosBeacon) -> Vec<u8> {
    let note_bytes = b.note.as_bytes();
    let note_len = note_bytes.len().min(MAX_NOTE_LEN);

    let mut out = Vec::with_capacity(20 + note_len);
    out.push(SOS_VERSION);
    out.extend_from_slice(&b.msg_id.to_be_bytes());
    out.push(b.ttl);
    out.push(b.priority);
    out.extend_from_slice(&b.sender_id);
    out.extend_from_slice(&b.lat_micro.to_be_bytes());
    out.extend_from_slice(&b.lon_micro.to_be_bytes());
    out.push(note_len as u8);
    out.extend_from_slice(&note_bytes[..note_len]);
    out
}

/// Decode a beacon from its wire form. Returns None on malformed input.
pub fn decode_sos(raw: &[u8]) -> Option<SosBeacon> {
    // Fixed prefix is 20 bytes, then note_len byte, then note.
    if raw.len() < 20 {
        return None;
    }
    if raw[0] != SOS_VERSION {
        return None;
    }
    let msg_id = u32::from_be_bytes([raw[1], raw[2], raw[3], raw[4]]);
    let ttl = raw[5];
    let priority = raw[6];
    let sender_id = [raw[7], raw[8], raw[9], raw[10]];
    let lat_micro = i32::from_be_bytes([raw[11], raw[12], raw[13], raw[14]]);
    let lon_micro = i32::from_be_bytes([raw[15], raw[16], raw[17], raw[18]]);
    let note_len = raw[19] as usize;

    let note_start: usize = 20;
    let note_end = note_start.checked_add(note_len)?;
    if raw.len() < note_end {
        return None;
    }
    let note = String::from_utf8_lossy(&raw[note_start..note_end]).into_owned();

    Some(SosBeacon {
        msg_id,
        ttl,
        priority,
        sender_id,
        lat_micro,
        lon_micro,
        note,
    })
}

/// Split a payload into BLE-advertisement-sized frames.
///
/// Each frame: msg_id(4 BE) total(1) index(1) chunk(..). `mtu` is the max bytes
/// per advertisement service-data; chunk size is `mtu - FRAME_HEADER`.
/// Panics-free: a too-small mtu falls back to 1 payload byte per frame.
pub fn fragment_beacon(msg_id: u32, payload: &[u8], mtu: usize) -> Vec<Vec<u8>> {
    let chunk_size = mtu.saturating_sub(FRAME_HEADER).max(1);
    let chunks: Vec<&[u8]> = if payload.is_empty() {
        vec![&payload[..]]
    } else {
        payload.chunks(chunk_size).collect()
    };
    let total = chunks.len().min(255) as u8;

    chunks
        .into_iter()
        .take(255)
        .enumerate()
        .map(|(idx, data)| {
            let mut frame = Vec::with_capacity(FRAME_HEADER + data.len());
            frame.extend_from_slice(&msg_id.to_be_bytes());
            frame.push(total);
            frame.push(idx as u8);
            frame.extend_from_slice(data);
            frame
        })
        .collect()
}

/// Parsed view of a single advertisement frame.
struct FrameHeader {
    msg_id: u32,
    total: u8,
    index: u8,
}

fn parse_frame(frame: &[u8]) -> Option<(FrameHeader, &[u8])> {
    if frame.len() < FRAME_HEADER {
        return None;
    }
    let msg_id = u32::from_be_bytes([frame[0], frame[1], frame[2], frame[3]]);
    let total = frame[4];
    let index = frame[5];
    if total == 0 || index >= total {
        return None;
    }
    Some((
        FrameHeader {
            msg_id,
            total,
            index,
        },
        &frame[FRAME_HEADER..],
    ))
}

/// In-progress reassembly of one message.
struct Partial {
    total: u8,
    chunks: HashMap<u8, Vec<u8>>,
    /// Monotonic insertion tick of last activity, for pruning.
    last_tick: u64,
}

/// Reassembles advertisement frames into full payloads, with dedup.
///
/// Stateful and single-threaded by design; the FFI layer wraps it in a Mutex.
/// `tick` is a caller-supplied monotonic counter (e.g. millis) used only for
/// relative ordering during pruning — never for wall-clock logic.
pub struct BeaconReassembler {
    partials: HashMap<u32, Partial>,
    /// msg_ids already fully delivered, so we never emit the same SOS twice.
    delivered: std::collections::HashSet<u32>,
    /// Bounded order of delivered ids for FIFO eviction.
    delivered_order: std::collections::VecDeque<u32>,
    max_delivered: usize,
}

impl Default for BeaconReassembler {
    fn default() -> Self {
        Self::new()
    }
}

impl BeaconReassembler {
    pub fn new() -> Self {
        BeaconReassembler {
            partials: HashMap::new(),
            delivered: std::collections::HashSet::new(),
            delivered_order: std::collections::VecDeque::new(),
            max_delivered: 512,
        }
    }

    /// True if this msg_id was already fully reassembled and emitted.
    pub fn already_delivered(&self, msg_id: u32) -> bool {
        self.delivered.contains(&msg_id)
    }

    /// Feed one received frame. Returns the full payload exactly once, when the
    /// final missing fragment of a not-yet-delivered message arrives.
    pub fn push_frame(&mut self, frame: &[u8], tick: u64) -> Option<Vec<u8>> {
        let (hdr, chunk) = parse_frame(frame)?;

        if self.delivered.contains(&hdr.msg_id) {
            return None; // duplicate of an already-emitted SOS
        }

        let entry = self.partials.entry(hdr.msg_id).or_insert_with(|| Partial {
            total: hdr.total,
            chunks: HashMap::new(),
            last_tick: tick,
        });
        // Guard against conflicting `total` across frames of the same id.
        if entry.total != hdr.total {
            return None;
        }
        entry.last_tick = tick;
        entry.chunks.insert(hdr.index, chunk.to_vec());

        if entry.chunks.len() as u8 != entry.total {
            return None; // still waiting for fragments
        }

        // All fragments present: assemble in index order.
        let mut payload = Vec::new();
        for i in 0..entry.total {
            payload.extend_from_slice(entry.chunks.get(&i)?);
        }
        self.partials.remove(&hdr.msg_id);
        self.mark_delivered(hdr.msg_id);
        Some(payload)
    }

    fn mark_delivered(&mut self, msg_id: u32) {
        if self.delivered.insert(msg_id) {
            self.delivered_order.push_back(msg_id);
            while self.delivered_order.len() > self.max_delivered {
                if let Some(old) = self.delivered_order.pop_front() {
                    self.delivered.remove(&old);
                }
            }
        }
    }

    /// Drop partial messages older than `max_age` ticks. Call periodically.
    pub fn prune(&mut self, now_tick: u64, max_age: u64) {
        self.partials
            .retain(|_, p| now_tick.saturating_sub(p.last_tick) <= max_age);
    }
}

/// Convenience: produce the relay form of a beacon (ttl decremented), or None
/// when the beacon has expired and must not be re-advertised.
pub fn relay_beacon(mut b: SosBeacon) -> Option<SosBeacon> {
    if b.ttl == 0 {
        return None;
    }
    b.ttl -= 1;
    if b.ttl == 0 {
        return None;
    }
    Some(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> SosBeacon {
        SosBeacon {
            msg_id: 0xDEAD_BEEF,
            ttl: 5,
            priority: PRIORITY_CRITICAL,
            sender_id: [1, 2, 3, 4],
            lat_micro: 10_491_016,   // ~10.491016 (Caracas)
            lon_micro: -66_902_500,  // ~-66.9025
            note: "Atrapado, 2 personas".to_string(),
        }
    }

    #[test]
    fn encode_decode_roundtrip() {
        let b = sample();
        let raw = encode_sos(&b);
        let got = decode_sos(&raw).expect("decode");
        assert_eq!(b, got);
        assert!(got.has_location());
    }

    #[test]
    fn decode_rejects_truncated() {
        assert!(decode_sos(&[]).is_none());
        assert!(decode_sos(&[1, 2, 3]).is_none());
        let mut raw = encode_sos(&sample());
        raw.truncate(raw.len() - 3); // chop part of the note
        assert!(decode_sos(&raw).is_none());
    }

    #[test]
    fn no_location_sentinel() {
        let mut b = sample();
        b.lat_micro = i32::MIN;
        b.lon_micro = i32::MIN;
        let got = decode_sos(&encode_sos(&b)).unwrap();
        assert!(!got.has_location());
    }

    #[test]
    fn fragment_and_reassemble() {
        let b = sample();
        let payload = encode_sos(&b);
        let frames = fragment_beacon(b.msg_id, &payload, 20);
        assert!(frames.len() > 1, "payload should need multiple frames");

        let mut r = BeaconReassembler::new();
        let mut result = None;
        for (i, f) in frames.iter().enumerate() {
            let out = r.push_frame(f, i as u64);
            if out.is_some() {
                result = out;
            }
        }
        let assembled = result.expect("reassembled payload");
        assert_eq!(assembled, payload);
        assert_eq!(decode_sos(&assembled).unwrap(), b);
    }

    #[test]
    fn reassemble_out_of_order_and_with_duplicates() {
        let b = sample();
        let payload = encode_sos(&b);
        let mut frames = fragment_beacon(b.msg_id, &payload, 16);
        frames.reverse(); // out of order

        let mut r = BeaconReassembler::new();
        let mut result = None;
        // Feed each frame twice to simulate repeated advertisements.
        for round in 0..2 {
            for (i, f) in frames.iter().enumerate() {
                if let Some(out) = r.push_frame(f, (round * 100 + i) as u64) {
                    result = Some(out);
                }
            }
        }
        assert_eq!(result.expect("assembled"), payload);
        // Once delivered, further frames must not re-emit.
        assert!(r.already_delivered(b.msg_id));
        assert!(r.push_frame(&frames[0], 999).is_none());
    }

    #[test]
    fn prune_drops_stale_partials() {
        let b = sample();
        let payload = encode_sos(&b);
        let frames = fragment_beacon(b.msg_id, &payload, 16);

        let mut r = BeaconReassembler::new();
        // Feed only the first fragment, then prune far in the future.
        assert!(r.push_frame(&frames[0], 0).is_none());
        r.prune(10_000, 1_000);
        // The remaining fragments arrive but the partial was pruned, so it
        // restarts and still completes once all are re-sent.
        let mut result = None;
        for (i, f) in frames.iter().enumerate() {
            if let Some(out) = r.push_frame(f, 10_001 + i as u64) {
                result = Some(out);
            }
        }
        assert_eq!(result.unwrap(), payload);
    }

    #[test]
    fn relay_decrements_and_expires() {
        let mut b = sample();
        b.ttl = 2;
        let r1 = relay_beacon(b.clone()).unwrap();
        assert_eq!(r1.ttl, 1);
        assert!(relay_beacon(r1).is_none()); // 1 -> 0, dropped
        b.ttl = 0;
        assert!(relay_beacon(b).is_none());
    }

    #[test]
    fn empty_payload_makes_one_frame() {
        let frames = fragment_beacon(7, &[], 20);
        assert_eq!(frames.len(), 1);
        let mut r = BeaconReassembler::new();
        assert_eq!(r.push_frame(&frames[0], 0), Some(vec![]));
    }
}
