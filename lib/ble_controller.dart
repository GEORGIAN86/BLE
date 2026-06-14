import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_service.dart';
import 'models.dart';

/// Aggregates the [BleService] streams into a single observable state object
/// for the UI. Mirrors the combined state the SwiftUI views observed across
/// `BLEManager` and `BLEPeripheralManager`.
class BleController extends ChangeNotifier {
  BleController(this._service) {
    _subs = [
      _service.bluetoothOn.listen((on) {
        isBluetoothOn = on;
        notifyListeners();
      }),
      _service.devices.listen((list) {
        peripherals = list;
        notifyListeners();
      }),
      _service.connectedId.listen((id) {
        connectedPeripheralId = id;
        notifyListeners();
      }),
      _service.services.listen((list) {
        services = list;
        notifyListeners();
      }),
      _service.advertising.listen((state) {
        advertising = state;
        notifyListeners();
      }),
    ];
  }

  final BleService _service;
  late final List<StreamSubscription<dynamic>> _subs;

  bool isBluetoothOn = false;
  List<Peripheral> peripherals = const [];
  String? connectedPeripheralId;
  List<DiscoveredService> services = const [];
  AdvertisingState advertising = const AdvertisingState();

  // Commands -------------------------------------------------------------

  Future<void> startScan() => _service.startScan();
  Future<void> stopScan() {
    peripherals = const [];
    notifyListeners();
    return _service.stopScan();
  }

  Future<void> connect(String id) {
    // Clear stale services while the new connection's GATT is discovered.
    services = const [];
    notifyListeners();
    return _service.connect(id);
  }

  Future<void> startClone(String name) => _service.startClone(name);
  Future<void> stopClone() => _service.stopClone();

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
