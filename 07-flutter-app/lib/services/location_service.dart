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

/// GPS location for emergency beacons. Works offline — GPS does not need
/// internet or cell towers, which is exactly the disaster scenario.
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LatLon {
  final double lat;
  final double lon;
  const LatLon(this.lat, this.lon);
}

class LocationService {
  /// Best-effort, fast position for attaching to an SOS.
  ///
  /// Strategy tuned for a person in distress:
  ///   1. return the last known fix instantly if available (no waiting), then
  ///   2. fall back to a fresh fix with a short time limit.
  /// Returns null if permission is denied or no fix arrives in time — the SOS
  /// is still sent without coordinates rather than blocking on GPS.
  static Future<LatLon?> getQuickPosition({
    Duration timeLimit = const Duration(seconds: 5),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await _lastKnown();
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return await _lastKnown();
      }

      // Instant cached fix first.
      final last = await _lastKnown();

      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: timeLimit,
        );
        return LatLon(pos.latitude, pos.longitude);
      } catch (_) {
        return last; // timed out / unavailable → use cached if any
      }
    } catch (e) {
      debugPrint('LocationService error: $e');
      return null;
    }
  }

  static Future<LatLon?> _lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) return null;
      return LatLon(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}
