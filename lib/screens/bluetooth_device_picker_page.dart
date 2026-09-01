import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothDevicePickerPage extends StatefulWidget {
  const BluetoothDevicePickerPage({super.key});

  @override
  State<BluetoothDevicePickerPage> createState() => _BluetoothDevicePickerPageState();
}

class _BluetoothDevicePickerPageState extends State<BluetoothDevicePickerPage> {
  final Map<String, BluetoothDevice> _devices = {};
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    await _discoverySubscription?.cancel();
    await FlutterBluetoothSerial.instance.cancelDiscovery();
    if (mounted) {
      setState(() {
        _scanning = true;
        _error = null;
      });
    }

    try {
      final bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
      for (final device in bondedDevices) {
        _devices[device.address] = device;
      }
      if (mounted) setState(() {});

      _discoverySubscription = FlutterBluetoothSerial.instance.startDiscovery().listen(
        (result) {
          if (!mounted) return;
          setState(() => _devices[result.device.address] = result.device);
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _scanning = false;
            _error = 'Could not scan for Bluetooth devices.';
          });
        },
        onDone: () {
          if (mounted) setState(() => _scanning = false);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Could not load Bluetooth devices.';
      });
    }
  }

  Future<void> _select(BluetoothDevice device) async {
    await FlutterBluetoothSerial.instance.cancelDiscovery();
    await _discoverySubscription?.cancel();
    if (mounted) Navigator.of(context).pop(device);
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    FlutterBluetoothSerial.instance.cancelDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) {
        if (a.isBonded != b.isBonded) return a.isBonded ? -1 : 1;
        return (a.name ?? a.address).compareTo(b.name ?? b.address);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('SELECT BLUETOOTH DEVICE'),
        actions: [
          IconButton(
            tooltip: 'Scan again',
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Text(
                      _scanning ? 'Searching for nearby devices…' : 'No Bluetooth devices found.',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: Icon(
                          device.isBonded ? Icons.bluetooth_connected : Icons.bluetooth,
                          color: const Color(0xFF69F0AE),
                        ),
                        title: Text(device.name?.trim().isNotEmpty == true ? device.name! : 'Unknown device'),
                        subtitle: Text(device.address),
                        trailing: device.isBonded
                            ? const Chip(label: Text('PAIRED'))
                            : const Icon(Icons.chevron_right),
                        onTap: () => _select(device),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
