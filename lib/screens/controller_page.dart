import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/pressable_control.dart';
import 'bluetooth_device_picker_page.dart';

enum ControlMode { joystick, buttons }

class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key});

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSubscription;
  ControlMode _mode = ControlMode.buttons;
  bool _scanning = false;
  bool _connected = false;
  double _speed = 65;
  double _analogSteering = 0;
  double _analogThrottle = 0;
  DateTime _lastMoveSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _send('S');
    _inputSubscription?.cancel();
    _connection?.finish();
    FlutterBluetoothSerial.instance.cancelDiscovery();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connected) {
      await _send('S');
      await _connection?.finish();
      return;
    }

    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final bluetoothPermissions = [
      permissions[Permission.bluetoothScan],
      permissions[Permission.bluetoothConnect],
    ];
    if (bluetoothPermissions.any((status) => status?.isPermanentlyDenied ?? false)) {
      _message('Bluetooth permission is blocked. Enable it in Settings and try again.');
      return;
    }
    if (bluetoothPermissions.any((status) => !(status?.isGranted ?? false))) {
      _message('Bluetooth permission is required to find the robot.');
      return;
    }

    try {
      final enabled = await FlutterBluetoothSerial.instance.requestEnable();
      if (enabled != true) {
        _message('Bluetooth must be turned on to find the robot.');
        return;
      }
    } catch (_) {
      _message('Bluetooth must be turned on to find the robot.');
      return;
    }

    if (!mounted) return;
    setState(() => _scanning = true);
    try {
      final device = await Navigator.of(context).push<BluetoothDevice>(
        MaterialPageRoute(builder: (_) => const BluetoothDevicePickerPage()),
      );
      if (device != null) await _openDevice(device.address);
    } catch (_) {
      _message('Unable to open the Bluetooth device list.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openDevice(String address) async {
    try {
      final connection = await BluetoothConnection.toAddress(address);
      _connection = connection;
      await _inputSubscription?.cancel();
      _inputSubscription = connection.input?.listen(
        (_) {},
        onDone: _handleDisconnected,
      );
      if (mounted) setState(() => _connected = true);
      _message('Robot connected');
    } catch (_) {
      _message('Could not connect to the robot. Make sure it is turned on and nearby.');
    }
  }

  void _handleDisconnected() {
    _connection = null;
    if (mounted) setState(() => _connected = false);
  }

  Future<void> _send(String value) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;
    try {
      connection.output.add(Uint8List.fromList(utf8.encode('$value\n')));
      await connection.output.allSent;
    } catch (_) {
      _message('Could not send command');
    }
  }

  void _sendJoystick(double x, double y, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastMoveSent).inMilliseconds < 80) return;
    _lastMoveSent = now;
    final xValue = (x * 100).round().clamp(-100, 100);
    final yValue = (-y * 100).round().clamp(-100, 100);
    _send('M:$xValue,$yValue,${_speed.round()}');
  }

  void _setAnalogSteering(double value) {
    _analogSteering = value;
    _sendJoystick(_analogSteering, -_analogThrottle, force: true);
  }

  void _setAnalogThrottle(double value) {
    _analogThrottle = value;
    _sendJoystick(_analogSteering, -_analogThrottle, force: true);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, color: Color(0xFF69F0AE)),
                  const SizedBox(width: 9),
                  const Expanded(child: Text('FLEXON CONTROLLER', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
                  FilledButton.tonalIcon(
                    onPressed: _scanning ? null : _connect,
                    icon: Icon(_connected ? Icons.bluetooth_connected : Icons.bluetooth_searching),
                    label: Text(_scanning ? 'Scanning' : _connected ? 'Connected' : 'Connect'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SegmentedButton<ControlMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ControlMode.joystick, icon: Icon(Icons.radio_button_checked), label: Text('Analog')),
                    ButtonSegment(value: ControlMode.buttons, icon: Icon(Icons.gamepad), label: Text('Gamepad')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) {
                    _send('S');
                    _analogSteering = 0;
                    _analogThrottle = 0;
                    setState(() => _mode = selection.first);
                  },
                ),
              ]),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _mode == ControlMode.joystick
                          ? Center(child: FittedBox(child: RobotJoystick(
                              key: const ValueKey('joystick'),
                              enabled: true,
                              onMove: (x, _) => _setAnalogSteering(x),
                              onReleased: () => _setAnalogSteering(0),
                            )))
                          : DirectionButtons(
                              key: const ValueKey('buttons'),
                              enabled: true,
                              speed: _speed.round(),
                              send: _send,
                            ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: SpeedControl(
                        speed: _speed,
                        onChanged: (value) => setState(() => _speed = value),
                        onChangeEnd: (value) => _send('V:${value.round()}'),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: DriveButtons(
                        enabled: true,
                        speed: _speed.round(),
                        send: _send,
                        analogMode: _mode == ControlMode.joystick,
                        onAnalogThrottle: _setAnalogThrottle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpeedControl extends StatelessWidget {
  const SpeedControl({
    super.key,
    required this.speed,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double speed;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final gaugeSize = math.min(constraints.maxWidth, constraints.maxHeight * .72)
          .clamp(120.0, 210.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: gaugeSize,
            height: gaugeSize * .72,
            child: CustomPaint(
              painter: SpeedometerPainter(speed),
              child: Align(
                alignment: const Alignment(0, .48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${speed.round()}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                    const Text('MOTOR POWER %', style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 1.1)),
                  ],
                ),
              ),
            ),
          ),
          Row(children: [
            const Text('20', style: TextStyle(fontSize: 11, color: Colors.white54)),
            Expanded(child: Slider(
              value: speed,
              min: 20,
              max: 100,
              divisions: 16,
              label: '${speed.round()}%',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            )),
            const Text('100', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ],
      );
    });
  }
}

class SpeedometerPainter extends CustomPainter {
  const SpeedometerPainter(this.speed);
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .9);
    final radius = math.min(size.width * .43, size.height * .78);
    const start = math.pi;
    const sweep = math.pi;
    final base = Paint()
      ..color = const Color(0xFF26313C)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 13;
    final active = Paint()
      ..shader = const SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [Color(0xFF69F0AE), Color(0xFFFFC857), Color(0xFFFF5252)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 13;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, start, sweep, false, base);
    canvas.drawArc(rect, start, sweep * (speed / 100), false, active);

    final tickPaint = Paint()..strokeWidth = 2;
    for (var i = 0; i <= 10; i++) {
      final angle = start + sweep * i / 10;
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 17);
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius - (i.isEven ? 29 : 24));
      tickPaint.color = i * 10 <= speed ? Colors.white70 : Colors.white24;
      canvas.drawLine(inner, outer, tickPaint);
    }

    final needleAngle = start + sweep * (speed / 100);
    final needle = Paint()..color = Colors.white..strokeWidth = 4..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + Offset(math.cos(needleAngle), math.sin(needleAngle)) * (radius - 34), needle);
    canvas.drawCircle(center, 7, Paint()..color = const Color(0xFF69F0AE));
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) => oldDelegate.speed != speed;
}

class DriveButtons extends StatefulWidget {
  const DriveButtons({
    super.key,
    required this.enabled,
    required this.speed,
    required this.send,
    required this.analogMode,
    required this.onAnalogThrottle,
  });

  final bool enabled;
  final int speed;
  final Future<void> Function(String value) send;
  final bool analogMode;
  final ValueChanged<double> onAnalogThrottle;

  @override
  State<DriveButtons> createState() => _DriveButtonsState();
}

class _DriveButtonsState extends State<DriveButtons> {
  Timer? _repeatTimer;

  Future<void> _startDriving(String command) async {
    _repeatTimer?.cancel();
    await widget.send('S');
    void drive() {
      if (widget.analogMode) {
        widget.onAnalogThrottle(command == 'F' ? 1 : -1);
      } else {
        widget.send('$command:${widget.speed}');
      }
    }
    drive();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      drive();
    });
  }

  void _stopDriving() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    if (widget.analogMode) widget.onAnalogThrottle(0);
    widget.send('S');
  }

  @override
  void didUpdateWidget(covariant DriveButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _stopDriving();
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget driveButton({
      required String label,
      required IconData icon,
      required String command,
      required Color color,
    }) => PressableControl(
      enabled: widget.enabled,
      borderRadius: BorderRadius.circular(22),
      onPressed: () => _startDriving(command),
      onReleased: _stopDriving,
      child: Container(
        width: 156,
        height: 70,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: widget.enabled ? color : const Color(0xFF20252B),
          boxShadow: widget.enabled ? [BoxShadow(color: color.withValues(alpha: .28), blurRadius: 16)] : null,
          border: Border.all(color: Colors.white24, width: 2),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: widget.enabled ? Colors.white : Colors.white24),
            const SizedBox(width: 9),
            Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: .8, color: widget.enabled ? Colors.white : Colors.white24)),
          ],
        ),
      ),
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          driveButton(
            label: 'FORWARD',
            icon: Icons.keyboard_double_arrow_up,
            command: 'F',
            color: const Color(0xFF27AE60),
          ),
          const SizedBox(height: 18),
          driveButton(
            label: 'REVERSE',
            icon: Icons.keyboard_double_arrow_down,
            command: 'B',
            color: const Color(0xFF2979FF),
          ),
        ],
      ),
    );
  }
}

class RobotJoystick extends StatefulWidget {
  const RobotJoystick({super.key, required this.enabled, required this.onMove, required this.onReleased});
  final bool enabled;
  final void Function(double x, double y) onMove;
  final VoidCallback onReleased;

  @override
  State<RobotJoystick> createState() => _RobotJoystickState();
}

class _RobotJoystickState extends State<RobotJoystick> {
  double positionX = 0;

  void update(Offset local) {
    const travel = 82.0;
    final deltaX = (local.dx - 130).clamp(-travel, travel).toDouble();
    setState(() => positionX = deltaX);
    // Analog mode is steering-only. Forward/reverse remain on the right controls.
    widget.onMove(deltaX / travel, 0);
  }

  void release() {
    setState(() => positionX = 0);
    widget.onReleased();
  }

  @override
  Widget build(BuildContext context) {
    const width = 260.0;
    const height = 148.0;
    return Opacity(
      opacity: widget.enabled ? 1 : .45,
      child: GestureDetector(
        onPanStart: widget.enabled ? (event) => update(event.localPosition) : null,
        onPanUpdate: widget.enabled ? (event) => update(event.localPosition) : null,
        onPanEnd: widget.enabled ? (_) => release() : null,
        onPanCancel: widget.enabled ? release : null,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            color: const Color(0xFF151C24),
            border: Border.all(color: Colors.white12, width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Icon(Icons.chevron_left, size: 54, color: Colors.white12),
                  Icon(Icons.chevron_right, size: 54, color: Colors.white12),
                ],
              ),
              Transform.translate(
                offset: Offset(positionX, 0),
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF69F0AE),
                    boxShadow: [BoxShadow(color: const Color(0xFF69F0AE).withValues(alpha: .3), blurRadius: 24)],
                  ),
                  child: const Icon(Icons.control_camera, color: Color(0xFF0B0F14), size: 38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DirectionButtons extends StatefulWidget {
  const DirectionButtons({super.key, required this.enabled, required this.speed, required this.send});
  final bool enabled;
  final int speed;
  final Future<void> Function(String value) send;

  @override
  State<DirectionButtons> createState() => _DirectionButtonsState();
}

class _DirectionButtonsState extends State<DirectionButtons> {
  Timer? _repeatTimer;

  void _start(String command) {
    _repeatTimer?.cancel();
    widget.send('$command:${widget.speed}');
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      widget.send('$command:${widget.speed}');
    });
  }

  void _stop() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    widget.send('S');
  }

  @override
  void didUpdateWidget(covariant DirectionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _stop();
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget button(Widget child, String command, {double size = 64}) => PressableControl(
      enabled: widget.enabled,
      borderRadius: BorderRadius.circular(size / 2),
      onPressed: () => _start(command),
      onReleased: _stop,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.enabled ? const Color(0xFF202A35) : const Color(0xFF14191F),
          border: Border.all(color: Colors.white12),
        ),
        child: IconTheme(data: IconThemeData(size: 34, color: widget.enabled ? Colors.white : Colors.white24), child: Center(child: child)),
      ),
    );

    Widget dpadButton(IconData icon, String command) => button(Icon(icon), command, size: 58);
    return LayoutBuilder(builder: (context, constraints) {
      final scale = (constraints.maxHeight / 190).clamp(.72, 1.0).toDouble();
      return Transform.scale(
        scale: scale,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 178, height: 178, child: Stack(children: [
            Positioned(top: 0, left: 60, child: dpadButton(Icons.keyboard_arrow_up, 'F')),
            Positioned(top: 60, left: 0, child: dpadButton(Icons.keyboard_arrow_left, 'L')),
            Positioned(top: 60, right: 0, child: dpadButton(Icons.keyboard_arrow_right, 'R')),
            Positioned(bottom: 0, left: 60, child: dpadButton(Icons.keyboard_arrow_down, 'B')),
            Positioned(top: 65, left: 65, child: Container(width: 48, height: 48, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10161D)))),
          ])),
        ]),
      );
    });
  }
}
