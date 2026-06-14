import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Bridges Flutter to the native CoreBluetooth layer.
///
/// * Commands (Flutter -> native) go over a [MethodChannel].
/// * State updates (native -> Flutter) arrive over a single multiplexed
///   [EventChannel]. Each event is a map with a `type` discriminator; this
///   class demultiplexes them into typed broadcast streams that mirror the
///   `@Published` properties of the original SwiftUI managers.
class BleService {
  BleService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methods = methodChannel ?? const MethodChannel(methodChannelName),
        _events = eventChannel ?? const EventChannel(eventChannelName) {
    _eventSub = _events.receiveBroadcastStream().listen(
          _handleEvent,
          onError: _handleError,
        );
  }

  static const String methodChannelName = 'ble/methods';
  static const String eventChannelName = 'ble/events';

  final MethodChannel _methods;
  final EventChannel _events;
  StreamSubscription<dynamic>? _eventSub;

  // ---- State streams (mirror the SwiftUI @Published properties) ----

  final _bluetoothOn = StreamController<bool>.broadcast();
  final _devices = StreamController<List<Peripheral>>.broadcast();
  final _connectedId = StreamController<String?>.broadcast();
  final _services = StreamController<List<DiscoveredService>>.broadcast();
  final _advertising = StreamController<AdvertisingState>.broadcast();

  /// `true` when the Bluetooth radio is powered on.
  Stream<bool> get bluetoothOn => _bluetoothOn.stream;

  /// The current list of discovered peripherals.
  Stream<List<Peripheral>> get devices => _devices.stream;

  /// UUID of the connected peripheral, or `null` if none.
  Stream<String?> get connectedId => _connectedId.stream;

  /// Discovered GATT services for the connected peripheral.
  Stream<List<DiscoveredService>> get services => _services.stream;

  /// Advertising / clone state of the local peripheral.
  Stream<AdvertisingState> get advertising => _advertising.stream;

  // ---- Commands (Flutter -> native) ----

  Future<void> startScan() => _invoke('startScan');
  Future<void> stopScan() => _invoke('stopScan');
  Future<void> connect(String id) => _invoke('connect', {'id': id});

  /// Clone the currently-discovered GATT profile and start advertising it.
  /// The native layer already holds the discovered services, so only the
  /// advertised name needs to be sent.
  Future<void> startClone(String name) => _invoke('startClone', {'name': name});
  Future<void> stopClone() => _invoke('stopClone');

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      debugPrint('BLE command "$method" failed: ${e.message}');
      rethrow;
    }
  }

  // ---- Event demultiplexing ----

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    switch (type) {
      case 'state':
        _bluetoothOn.add((event['isOn'] as bool?) ?? false);
        break;
      case 'devices':
        final list = (event['devices'] as List<dynamic>?) ?? const [];
        _devices.add(
          list.map((d) => Peripheral.fromMap(d as Map)).toList(),
        );
        break;
      case 'connection':
        _connectedId.add(event['connectedId'] as String?);
        break;
      case 'services':
        final list = (event['services'] as List<dynamic>?) ?? const [];
        _services.add(
          list.map((s) => DiscoveredService.fromMap(s as Map)).toList(),
        );
        break;
      case 'advertising':
        _advertising.add(AdvertisingState.fromMap(event));
        break;
      default:
        debugPrint('BLE: unknown event type "$type"');
    }
  }

  void _handleError(Object error) {
    debugPrint('BLE event channel error: $error');
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _bluetoothOn.close();
    await _devices.close();
    await _connectedId.close();
    await _services.close();
    await _advertising.close();
  }
}
