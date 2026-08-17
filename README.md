# ESP32 Robot BLE Controller

Flutter app and Arduino IDE firmware for controlling a two-motor ESP32 robot over Bluetooth Low Energy.

## Included controls

- Connect/disconnect button
- Landscape controller with switchable steering joystick and four-direction D-pad modes
- Centre speedometer and adjustable maximum motor power (20–100%)
- Forward and Reverse hold controls on the right
- Release-to-brake behaviour; no separate Select, Start, or Stop buttons
- Automatic ESP32 motor stop after 500 ms without a movement command

## 1. Create and run the Flutter project

Install Flutter, then run these commands from the folder containing this project:

```bash
flutter create --platforms=android,ios robot_ble_controller_generated
cp -R robot_ble_controller/lib robot_ble_controller/pubspec.yaml robot_ble_controller_generated/
cp robot_ble_controller/android/app/src/main/AndroidManifest.xml robot_ble_controller_generated/android/app/src/main/AndroidManifest.xml
cd robot_ble_controller_generated
flutter pub get
flutter run
```

For iOS, copy the two Bluetooth keys in `ios/Runner/Info.plist.additions.xml` into the `<dict>` in the generated `ios/Runner/Info.plist`. BLE must be tested on a real phone, not a normal simulator.

## 2. Upload the Arduino firmware

1. Install Arduino IDE.
2. In Boards Manager, install **esp32 by Espressif Systems**.
3. Open `arduino/esp32_robot_ble/esp32_robot_ble.ino`.
4. Select the exact ESP32 board and port.
5. Check and change the six motor pins at the top of the sketch.
6. Disconnect or raise the robot wheels before the first upload/test.
7. Upload, then open Serial Monitor at 115200 baud.

The firmware uses the BLE library included with the Espressif ESP32 Arduino core; no separate BLE library should be required.

## Motor driver assumptions

The example expects two direction pins and one PWM/enable pin for each motor, as found on common L298N or TB6612-style motor drivers. Never power motors directly from ESP32 GPIO pins. The motor power ground and ESP32 ground must be connected.

If a motor turns backward, swap that motor's two direction-pin constants in the sketch or swap its motor wires. Confirm the actual board schematic before powering it.

## BLE protocol

| Command | Meaning |
|---|---|
| `M:x,y,speed` | Combined analog steering (`x`) and right-button throttle (`y`), each from -100 to 100 |
| `F:65` | Forward at 65% |
| `B:65` | Backward at 65% |
| `L:65` | Rotate left at 65% |
| `R:65` | Rotate right at 65% |
| `V:65` | Store maximum button speed |
| `S` | Stop immediately |

Both projects use the same service and characteristic UUIDs. If you change a UUID, change it in both `lib/main.dart` and the Arduino sketch.

The two left modes intentionally behave differently. In D-pad mode, Up/Down drive Forward/Reverse and Left/Right turn, allowing one-handed control. In Analog mode, the joystick moves horizontally only and controls steering; use the right Forward/Reverse buttons for throttle. The app combines both inputs into one `M:x,y,speed` command so steering and throttle work at the same time. Held D-pad and throttle commands repeat every 200 ms, and releasing a D-pad direction stops that action. The speed slider limits every movement command. The app locks the controller screen to landscape while it is open.

The speedometer shows requested motor power, not measured km/h. Actual vehicle speed requires wheel encoders and a BLE telemetry characteristic. Hold Forward or Reverse to move at the selected power. The app repeats the held command every 200 ms to satisfy the firmware safety timeout. Releasing either button sends `S`, which removes motor drive power and stops/coasts the robot. Pressing the opposite direction first sends `S` before changing direction to reduce sudden motor reversal. True active braking depends on the exact motor driver and is not enabled by this generic firmware.

## Important first test

Test with the wheels off the floor and a low speed. The included pin numbers are examples only because the robot's exact circuit and motor-driver model are not yet known.
