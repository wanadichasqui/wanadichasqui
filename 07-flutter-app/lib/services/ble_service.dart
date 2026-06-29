import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class BleService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  final StreamController<List<DiscoveredDevice>> _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  final List<DiscoveredDevice> _devices = [];

  bool _scanning = false;

  Stream<List<DiscoveredDevice>> get devices => _devicesController.stream;

  bool get isScanning => _scanning;

  Future<void> startScan() async {
    if (_scanning) return;

    _devices.clear();
    _devicesController.add([]);

    _scanning = true;

    _scanSubscription = _ble
        .scanForDevices(
          withServices: const [],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          _onDevice,
          onError: (error) {
            print("BLE Scan Error: $error");
            stopScan();
          },
        );
  }

  void _onDevice(DiscoveredDevice device) {
    final index = _devices.indexWhere((d) => d.id == device.id);

    if (index == -1) {
      _devices.add(device);
    } else {
      _devices[index] = device;
    }

    _devicesController.add(List<DiscoveredDevice>.from(_devices));
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanning = false;
  }

  void dispose() {
    _scanSubscription?.cancel();
    _devicesController.close();
  }
}
