import 'package:ble_app/ble_controller.dart';
import 'package:ble_app/ble_service.dart';
import 'package:ble_app/device_detail_view.dart';
import 'package:ble_app/main.dart';
import 'package:ble_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controller whose state can be driven directly from tests.
class TestController extends BleController {
  TestController(super.service);

  void set({
    bool? bluetoothOn,
    List<Peripheral>? devices,
    String? connectedId,
    List<DiscoveredService>? services,
    AdvertisingState? advertising,
  }) {
    if (bluetoothOn != null) isBluetoothOn = bluetoothOn;
    if (devices != null) peripherals = devices;
    connectedPeripheralId = connectedId ?? connectedPeripheralId;
    if (services != null) this.services = services;
    if (advertising != null) this.advertising = advertising;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late TestController controller;

  setUp(() {
    // Keep the BleService channels silent during widget tests.
    messenger.setMockMethodCallHandler(
        const MethodChannel(BleService.methodChannelName), (c) async => null);
    messenger.setMockStreamHandler(
      const EventChannel(BleService.eventChannelName),
      MockStreamHandler.inline(onListen: (a, s) {}),
    );
    controller = TestController(BleService());
  });

  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(
        const MethodChannel(BleService.methodChannelName), null);
    messenger.setMockStreamHandler(
        const EventChannel(BleService.eventChannelName), null);
  });

  Widget homeUnderTest() => MaterialApp(home: HomePage(controller: controller));

  testWidgets('status indicator and scan buttons reflect Bluetooth state',
      (tester) async {
    await tester.pumpWidget(homeUnderTest());
    expect(find.text('Bluetooth is OFF'), findsOneWidget);

    // Scan button disabled while off.
    final scanBtn =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Scanning'));
    expect(scanBtn.onPressed, isNull);

    controller.set(bluetoothOn: true);
    await tester.pump();
    expect(find.text('Bluetooth is ON'), findsOneWidget);
    final scanBtn2 =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Scanning'));
    expect(scanBtn2.onPressed, isNotNull);
  });

  testWidgets('empty state then device list renders name and rssi',
      (tester) async {
    await tester.pumpWidget(homeUnderTest());
    expect(find.textContaining('No devices found yet'), findsOneWidget);

    controller.set(
      bluetoothOn: true,
      devices: const [
        Peripheral(id: '1', name: 'Heart Monitor', rssi: -55),
        Peripheral(id: '2', name: 'Thermostat', rssi: -77),
      ],
    );
    await tester.pump();

    expect(find.text('Heart Monitor'), findsOneWidget);
    expect(find.text('-55 dBm'), findsOneWidget);
    expect(find.text('Thermostat'), findsOneWidget);
  });

  testWidgets('selecting a device shows detail with Connect & Clone action',
      (tester) async {
    controller.set(
      bluetoothOn: true,
      devices: const [Peripheral(id: '1', name: 'Heart Monitor', rssi: -55)],
    );
    await tester.pumpWidget(homeUnderTest());
    await tester.pump();

    await tester.tap(find.text('Heart Monitor'));
    await tester.pump();

    // Detail pane appears (device UUID shown) with the connect action.
    expect(find.text('Connect & Clone'), findsOneWidget);
    expect(find.text('Discovering services…'), findsNothing);
  });

  testWidgets('detail action becomes Clone when connected with services',
      (tester) async {
    const peripheral = Peripheral(id: '1', name: 'HM', rssi: -55);
    controller.set(
      bluetoothOn: true,
      connectedId: '1',
      services: const [
        DiscoveredService(
          uuid: '180D',
          characteristics: [
            DiscoveredCharacteristic(uuid: '2A37', rawProperties: 0x12),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeviceDetailView(controller: controller, peripheral: peripheral),
      ),
    ));
    await tester.pump();

    expect(find.text('Clone'), findsOneWidget);
    // 0x12 = read(0x02) + notify(0x10)
    expect(find.textContaining('Properties: Read, Notify'), findsOneWidget);
    expect(find.textContaining('Access: Readable, Notifiable'), findsOneWidget);
  });

  testWidgets('detail action becomes Stop while advertising', (tester) async {
    const peripheral = Peripheral(id: '1', name: 'HM', rssi: -55);
    controller.set(
      bluetoothOn: true,
      connectedId: '1',
      advertising:
          const AdvertisingState(isAdvertising: true, statusMessage: 'Broadcasting as "HM"'),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DeviceDetailView(controller: controller, peripheral: peripheral),
      ),
    ));
    await tester.pump();

    expect(find.text('Stop'), findsOneWidget);
    expect(find.textContaining('Broadcasting as "HM"'), findsOneWidget);
  });
}
