// PlatformIO/C++ entrypoint for the same FleXon controller firmware.
// The implementation is shared with the Arduino .ino version so both formats
// always use identical Bluetooth commands, motor controls, and safety logic.
// Keep this project separate from the .ino sketch to avoid duplicate setup()
// and loop() definitions during compilation.

#include <Arduino.h>
#include "../../esp32_robot_ble/esp32_robot_ble.ino"
