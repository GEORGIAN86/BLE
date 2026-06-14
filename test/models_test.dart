import 'package:ble_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiscoveredCharacteristic property derivation', () {
    test('read only', () {
      final ch = DiscoveredCharacteristic(
        uuid: '2A00',
        rawProperties: CharacteristicProperty.read,
      );
      expect(ch.properties, ['Read']);
      expect(ch.access, ['Readable']);
    });

    test('read + write + notify maps to all derived access', () {
      final raw = CharacteristicProperty.read |
          CharacteristicProperty.write |
          CharacteristicProperty.notify;
      final ch = DiscoveredCharacteristic(uuid: 'X', rawProperties: raw);
      expect(ch.properties, ['Read', 'Write', 'Notify']);
      expect(ch.access, ['Readable', 'Writable', 'Notifiable']);
    });

    test('writeWithoutResponse implies Writable access', () {
      final ch = DiscoveredCharacteristic(
        uuid: 'X',
        rawProperties: CharacteristicProperty.writeWithoutResponse,
      );
      expect(ch.properties, ['Write Without Response']);
      expect(ch.access, ['Writable']);
    });

    test('indicate implies Notifiable access', () {
      final ch = DiscoveredCharacteristic(
        uuid: 'X',
        rawProperties: CharacteristicProperty.indicate,
      );
      expect(ch.properties, ['Indicate']);
      expect(ch.access, ['Notifiable']);
    });

    test('property order matches Swift describeProperties', () {
      final raw = CharacteristicProperty.broadcast |
          CharacteristicProperty.read |
          CharacteristicProperty.writeWithoutResponse |
          CharacteristicProperty.write |
          CharacteristicProperty.notify |
          CharacteristicProperty.indicate |
          CharacteristicProperty.authenticatedSignedWrites |
          CharacteristicProperty.extendedProperties |
          CharacteristicProperty.notifyEncryptionRequired |
          CharacteristicProperty.indicateEncryptionRequired;
      final ch = DiscoveredCharacteristic(uuid: 'X', rawProperties: raw);
      expect(ch.properties, [
        'Broadcast',
        'Read',
        'Write Without Response',
        'Write',
        'Notify',
        'Indicate',
        'Signed Write',
        'Extended Properties',
        'Notify (Encrypted)',
        'Indicate (Encrypted)',
      ]);
    });

    test('zero properties => empty lists', () {
      final ch = DiscoveredCharacteristic(uuid: 'X', rawProperties: 0);
      expect(ch.properties, isEmpty);
      expect(ch.access, isEmpty);
    });
  });

  group('Serialization round-trips', () {
    test('Peripheral.fromMap / toMap', () {
      final p = Peripheral.fromMap({'id': 'uuid-1', 'name': 'Watch', 'rssi': -73});
      expect(p.id, 'uuid-1');
      expect(p.name, 'Watch');
      expect(p.rssi, -73);
      expect(p.toMap(), {'id': 'uuid-1', 'name': 'Watch', 'rssi': -73});
    });

    test('Peripheral defaults missing name to Unknown', () {
      final p = Peripheral.fromMap({'id': 'uuid-1', 'rssi': -50});
      expect(p.name, 'Unknown');
    });

    test('Peripheral equality is by id', () {
      const a = Peripheral(id: 'x', name: 'A', rssi: -1);
      const b = Peripheral(id: 'x', name: 'B', rssi: -99);
      expect(a, equals(b));
    });

    test('DiscoveredService.fromMap parses nested characteristics', () {
      final svc = DiscoveredService.fromMap({
        'uuid': '180D',
        'isPrimary': true,
        'characteristics': [
          {'uuid': '2A37', 'rawProperties': CharacteristicProperty.notify},
        ],
      });
      expect(svc.uuid, '180D');
      expect(svc.isPrimary, isTrue);
      expect(svc.characteristics, hasLength(1));
      expect(svc.characteristics.first.properties, ['Notify']);
    });

    test('rawProperties survives round-trip through a map (clone fidelity)', () {
      final raw =
          CharacteristicProperty.read | CharacteristicProperty.indicate;
      final original =
          DiscoveredCharacteristic(uuid: '2A05', rawProperties: raw);
      final restored = DiscoveredCharacteristic.fromMap(original.toMap());
      expect(restored.rawProperties, raw);
      expect(restored.uuid, '2A05');
    });

    test('AdvertisingState.fromMap', () {
      final s = AdvertisingState.fromMap(
          {'isAdvertising': true, 'status': 'Broadcasting as "X"'});
      expect(s.isAdvertising, isTrue);
      expect(s.statusMessage, 'Broadcasting as "X"');
    });
  });
}
