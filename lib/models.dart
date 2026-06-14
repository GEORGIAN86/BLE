/// Data models for the BLE Scanner / GATT cloner.
///
/// These mirror the Swift structs in the original SwiftUI app
/// (`Peripheral`, `DiscoveredService`, `DiscoveredCharacteristic`) but are
/// built from plain maps that arrive over the platform [EventChannel].
///
/// Important: CoreBluetooth objects (CBPeripheral / CBService /
/// CBCharacteristic / CBCharacteristicProperties) are NEVER sent across the
/// channel — only serializable primitives are. The characteristic's
/// `CBCharacteristicProperties` OptionSet is transmitted as its raw integer
/// bitmask and the human-readable property/access lists are derived here in
/// Dart, which keeps the native layer thin and makes this logic unit-testable.
library;

/// Raw bit values of `CBCharacteristicProperties` (CoreBluetooth).
/// Kept identical to Apple's definitions so the native clone can reconstruct
/// the exact same OptionSet from the integer we round-trip.
class CharacteristicProperty {
  static const int broadcast = 0x01;
  static const int read = 0x02;
  static const int writeWithoutResponse = 0x04;
  static const int write = 0x08;
  static const int notify = 0x10;
  static const int indicate = 0x20;
  static const int authenticatedSignedWrites = 0x40;
  static const int extendedProperties = 0x80;
  static const int notifyEncryptionRequired = 0x100;
  static const int indicateEncryptionRequired = 0x200;
}

/// A discovered BLE peripheral (advertising device).
class Peripheral {
  final String id; // CBPeripheral.identifier as a UUID string
  final String name; // advertised name or "Unknown"
  final int rssi; // signal strength in dBm (more negative = weaker)

  const Peripheral({required this.id, required this.name, required this.rssi});

  factory Peripheral.fromMap(Map<dynamic, dynamic> map) {
    return Peripheral(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? 'Unknown',
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'rssi': rssi};

  @override
  bool operator ==(Object other) => other is Peripheral && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A single GATT characteristic.
class DiscoveredCharacteristic {
  final String uuid;

  /// Raw `CBCharacteristicProperties` bitmask as received from native.
  final int rawProperties;

  const DiscoveredCharacteristic({
    required this.uuid,
    required this.rawProperties,
  });

  factory DiscoveredCharacteristic.fromMap(Map<dynamic, dynamic> map) {
    return DiscoveredCharacteristic(
      uuid: map['uuid'] as String,
      rawProperties: (map['rawProperties'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {'uuid': uuid, 'rawProperties': rawProperties};

  bool _has(int flag) => (rawProperties & flag) != 0;

  /// Human-readable property names (matches the order of the original
  /// Swift `describeProperties`).
  List<String> get properties {
    final names = <String>[];
    if (_has(CharacteristicProperty.broadcast)) names.add('Broadcast');
    if (_has(CharacteristicProperty.read)) names.add('Read');
    if (_has(CharacteristicProperty.writeWithoutResponse)) {
      names.add('Write Without Response');
    }
    if (_has(CharacteristicProperty.write)) names.add('Write');
    if (_has(CharacteristicProperty.notify)) names.add('Notify');
    if (_has(CharacteristicProperty.indicate)) names.add('Indicate');
    if (_has(CharacteristicProperty.authenticatedSignedWrites)) {
      names.add('Signed Write');
    }
    if (_has(CharacteristicProperty.extendedProperties)) {
      names.add('Extended Properties');
    }
    if (_has(CharacteristicProperty.notifyEncryptionRequired)) {
      names.add('Notify (Encrypted)');
    }
    if (_has(CharacteristicProperty.indicateEncryptionRequired)) {
      names.add('Indicate (Encrypted)');
    }
    return names;
  }

  /// Inferred access (a central can't read GATT permissions directly, so this
  /// is derived from the advertised properties — matches Swift `deriveAccess`).
  List<String> get access {
    final result = <String>[];
    if (_has(CharacteristicProperty.read)) result.add('Readable');
    if (_has(CharacteristicProperty.write) ||
        _has(CharacteristicProperty.writeWithoutResponse)) {
      result.add('Writable');
    }
    if (_has(CharacteristicProperty.notify) ||
        _has(CharacteristicProperty.indicate)) {
      result.add('Notifiable');
    }
    return result;
  }
}

/// A GATT service plus its characteristics.
class DiscoveredService {
  final String uuid;
  final bool isPrimary;
  final List<DiscoveredCharacteristic> characteristics;

  const DiscoveredService({
    required this.uuid,
    this.isPrimary = true,
    this.characteristics = const [],
  });

  factory DiscoveredService.fromMap(Map<dynamic, dynamic> map) {
    final rawChars = (map['characteristics'] as List<dynamic>?) ?? const [];
    return DiscoveredService(
      uuid: map['uuid'] as String,
      isPrimary: (map['isPrimary'] as bool?) ?? true,
      characteristics: rawChars
          .map((c) => DiscoveredCharacteristic.fromMap(c as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'isPrimary': isPrimary,
    'characteristics': characteristics.map((c) => c.toMap()).toList(),
  };
}

/// Snapshot of the peripheral (advertiser / clone) state.
class AdvertisingState {
  final bool isAdvertising;
  final String statusMessage;

  const AdvertisingState({
    this.isAdvertising = false,
    this.statusMessage = '',
  });

  factory AdvertisingState.fromMap(Map<dynamic, dynamic> map) {
    return AdvertisingState(
      isAdvertising: (map['isAdvertising'] as bool?) ?? false,
      statusMessage: (map['status'] as String?) ?? '',
    );
  }
}
