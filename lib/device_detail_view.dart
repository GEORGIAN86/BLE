import 'package:flutter/material.dart';

import 'ble_controller.dart';
import 'models.dart';

/// Detail pane: device info, discovered services/characteristics, the
/// broadcast banner, and the Connect / Clone / Stop action button.
///
/// Mirrors the SwiftUI `DeviceDetailView` and its action-button state machine.
class DeviceDetailView extends StatefulWidget {
  const DeviceDetailView({
    super.key,
    required this.controller,
    required this.peripheral,
  });

  final BleController controller;
  final Peripheral peripheral;

  @override
  State<DeviceDetailView> createState() => _DeviceDetailViewState();
}

class _DeviceDetailViewState extends State<DeviceDetailView> {
  bool _isConnecting = false;

  BleController get c => widget.controller;
  Peripheral get p => widget.peripheral;

  bool get _isConnected => c.connectedPeripheralId == p.id;

  @override
  Widget build(BuildContext context) {
    // Stop showing the spinner once this device becomes the connected one.
    if (_isConnecting && _isConnected) {
      _isConnecting = false;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [_buildActionButton(context)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          if (c.advertising.statusMessage.isNotEmpty) _buildBroadcastBanner(),
          _buildDeviceSection(),
          ..._buildServicesSection(),
        ],
      ),
    );
  }

  Widget _buildBroadcastBanner() {
    final adv = c.advertising;
    final color = adv.isAdvertising ? Colors.green : Colors.grey;
    return Card(
      color: color.withValues(alpha: 0.12),
      child: ListTile(
        leading: Icon(
          adv.isAdvertising ? Icons.settings_input_antenna : Icons.info_outline,
          color: color,
        ),
        title: const Text('Broadcast'),
        subtitle: Text(adv.statusMessage),
      ),
    );
  }

  Widget _buildDeviceSection() {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Name'),
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('UUID'),
            subtitle: SelectableText(p.id),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildServicesSection() {
    if (c.services.isEmpty) {
      // Only show the discovery spinner once we're actually connected to
      // this device; before connecting there's nothing to discover yet.
      if (!_isConnected) return const [];
      return [
        const Card(
          child: ListTile(
            leading: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Discovering services…'),
          ),
        ),
      ];
    }
    return c.services.map(_buildServiceCard).toList();
  }

  Widget _buildServiceCard(DiscoveredService service) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Service ${service.uuid}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final ch in service.characteristics) _buildCharacteristic(ch),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCharacteristic(DiscoveredCharacteristic ch) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(ch.uuid, style: const TextStyle(fontSize: 13)),
          if (ch.properties.isNotEmpty)
            Text(
              'Properties: ${ch.properties.join(", ")}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          if (ch.access.isNotEmpty)
            Text(
              'Access: ${ch.access.join(", ")}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  /// The single context-aware action button (matches the SwiftUI toolbar item).
  Widget _buildActionButton(BuildContext context) {
    final adv = c.advertising;

    // 1) Currently advertising -> Stop
    if (adv.isAdvertising) {
      return TextButton(
        onPressed: () => c.stopClone(),
        child: const Text('Stop'),
      );
    }

    // 2) Connected with services discovered -> Clone
    if (_isConnected && c.services.isNotEmpty) {
      return TextButton(
        onPressed: () {
          c.stopScan();
          c.startClone(p.name);
        },
        child: const Text('Clone'),
      );
    }

    // 3) Connected but still discovering services -> Clone (disabled, spinner)
    if (_isConnected) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // 4) Not connected -> Connect & Clone
    return TextButton(
      onPressed: (_isConnecting || !c.isBluetoothOn)
          ? null
          : () {
              setState(() => _isConnecting = true);
              c.connect(p.id);
            },
      child: Text(_isConnecting ? 'Connecting…' : 'Connect & Clone'),
    );
  }
}
