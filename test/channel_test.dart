import 'package:ble_app/ble_controller.dart';
import 'package:ble_app/ble_service.dart';
import 'package:ble_app/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('MethodChannel commands', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(
        const MethodChannel(BleService.methodChannelName),
        (call) async {
          calls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(
          const MethodChannel(BleService.methodChannelName), null);
    });

    test('commands invoke the platform channel with correct arguments',
        () async {
      final service = BleService();
      await service.startScan();
      await service.stopScan();
      await service.connect('dev-1');
      await service.startClone('My Phone');
      await service.stopClone();

      expect(calls.map((c) => c.method).toList(), [
        'startScan',
        'stopScan',
        'connect',
        'startClone',
        'stopClone',
      ]);
      expect(calls[2].arguments, {'id': 'dev-1'});
      expect(calls[3].arguments, {'name': 'My Phone'});
      await service.dispose();
    });
  });

  group('EventChannel demultiplexing -> BleController', () {
    setUp(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel(BleService.methodChannelName),
        (call) async => null,
      );
    });

    tearDown(() {
      messenger.setMockStreamHandler(
          const EventChannel(BleService.eventChannelName), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel(BleService.methodChannelName), null);
    });

    test('state / devices / connection / services / advertising route correctly',
        () async {
      messenger.setMockStreamHandler(
        const EventChannel(BleService.eventChannelName),
        MockStreamHandler.inline(
          onListen: (args, sink) {
            sink.success({'type': 'state', 'isOn': true});
            sink.success({
              'type': 'devices',
              'devices': [
                {'id': '1', 'name': 'A', 'rssi': -40},
                {'id': '2', 'name': 'B', 'rssi': -88},
              ],
            });
            sink.success({'type': 'connection', 'connectedId': '1'});
            sink.success({
              'type': 'services',
              'services': [
                {
                  'uuid': '180D',
                  'isPrimary': true,
                  'characteristics': [
                    {'uuid': '2A37', 'rawProperties': CharacteristicProperty.notify},
                  ],
                },
              ],
            });
            sink.success({
              'type': 'advertising',
              'isAdvertising': true,
              'status': 'Broadcasting as "A"',
            });
          },
        ),
      );

      final service = BleService();
      final controller = BleController(service);
      await pumpEventQueue();

      expect(controller.isBluetoothOn, isTrue);
      expect(controller.peripherals.map((p) => p.name), ['A', 'B']);
      expect(controller.peripherals[1].rssi, -88);
      expect(controller.connectedPeripheralId, '1');
      expect(controller.services, hasLength(1));
      expect(controller.services.first.characteristics.first.properties,
          ['Notify']);
      expect(controller.advertising.isAdvertising, isTrue);
      expect(controller.advertising.statusMessage, 'Broadcasting as "A"');

      controller.dispose();
      await service.dispose();
    });

    test('unknown event types are ignored without throwing', () async {
      messenger.setMockStreamHandler(
        const EventChannel(BleService.eventChannelName),
        MockStreamHandler.inline(
          onListen: (args, sink) {
            sink.success({'type': 'totally-unknown'});
            sink.success({'type': 'state', 'isOn': true});
          },
        ),
      );

      final service = BleService();
      final controller = BleController(service);
      await pumpEventQueue();

      expect(controller.isBluetoothOn, isTrue);
      controller.dispose();
      await service.dispose();
    });
  });
}
