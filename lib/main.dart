import 'package:flutter/material.dart';

import 'ble_controller.dart';
import 'ble_service.dart';
import 'device_detail_view.dart';
import 'models.dart';

void main() {
  runApp(const BlueApp());
}

class BlueApp extends StatefulWidget {
  const BlueApp({super.key});

  @override
  State<BlueApp> createState() => _BlueAppState();
}

class _BlueAppState extends State<BlueApp> {
  late final BleService _service;
  late final BleController _controller;

  @override
  void initState() {
    super.initState();
    _service = BleService();
    _controller = BleController(_service);
  }

  @override
  void dispose() {
    _controller.dispose();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLUE — BLE Scanner',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: HomePage(controller: _controller),
    );
  }
}

/// Top-level split view: a sidebar (status + device list + scan controls) and
/// a detail pane. Mirrors the SwiftUI `NavigationSplitView`.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final BleController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selectedId;

  BleController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        // Keep the selection valid if the device list changes.
        final selected = c.peripherals
            .where((p) => p.id == _selectedId)
            .cast<Peripheral?>()
            .firstWhere((_) => true, orElse: () => null);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            final sidebar = _Sidebar(
              controller: c,
              selectedId: _selectedId,
              onSelect: (id) => _onSelect(id, isWide),
            );

            if (isWide) {
              return Scaffold(
                body: Row(
                  children: [
                    SizedBox(width: 340, child: sidebar),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected == null
                          ? const _DetailPlaceholder()
                          : DeviceDetailView(
                              key: ValueKey(selected.id),
                              controller: c,
                              peripheral: selected,
                            ),
                    ),
                  ],
                ),
              );
            }

            // Narrow layout: sidebar only; selection pushes a detail route.
            return sidebar;
          },
        );
      },
    );
  }

  void _onSelect(String id, bool isWide) {
    setState(() => _selectedId = id);
    if (!isWide) {
      final peripheral = c.peripherals.firstWhere((p) => p.id == id);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ListenableBuilder(
            listenable: c,
            builder: (_, _) =>
                DeviceDetailView(controller: c, peripheral: peripheral),
          ),
        ),
      );
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.selectedId,
    required this.onSelect,
  });

  final BleController controller;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Devices')),
      body: Column(
        children: [
          _statusRow(c.isBluetoothOn),
          const Divider(height: 1),
          Expanded(
            child: c.peripherals.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No devices found yet.\nTap Start Scanning to begin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: c.peripherals.length,
                    itemBuilder: (context, i) {
                      final p = c.peripherals[i];
                      final isConnected = c.connectedPeripheralId == p.id;
                      return ListTile(
                        selected: p.id == selectedId,
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          p.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${p.rssi} dBm',
                                style: const TextStyle(color: Colors.grey)),
                            if (isConnected)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.check_circle,
                                    color: Colors.green, size: 18),
                              ),
                          ],
                        ),
                        onTap: () => onSelect(p.id),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          _scanControls(c),
        ],
      ),
    );
  }

  Widget _statusRow(bool on) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: on ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            on ? 'Bluetooth is ON' : 'Bluetooth is OFF',
            style: TextStyle(color: on ? Colors.green : Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _scanControls(BleController c) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: c.isBluetoothOn ? () => c.startScan() : null,
              child: const Text('Start Scanning'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: c.isBluetoothOn ? () => c.stopScan() : null,
              child: const Text('Stop Scanning'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Select a device to view its services and characteristics.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
