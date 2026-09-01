#include <Arduino.h>
#include "BluetoothSerial.h"

BluetoothSerial SerialBT;

// Change if the FleXon motor-driver wiring is different.
const int LEFT_IN1 = 26;
const int LEFT_IN2 = 27;
const int LEFT_PWM = 25;
const int RIGHT_IN1 = 14;
const int RIGHT_IN2 = 12;
const int RIGHT_PWM = 13;

// Stop the robot if movement commands stop arriving from the app.
const unsigned long COMMAND_TIMEOUT_MS = 500;

unsigned long lastMovementAt = 0;
int maximumSpeed = 65;
String receivedCommand;

// Set one motor's direction and speed.
void driveOneMotor(int in1, int in2, int pwmPin, int value) {
  value = constrain(value, -255, 255);
  if (value > 0) {
    digitalWrite(in1, HIGH);
    digitalWrite(in2, LOW);
  } else if (value < 0) {
    digitalWrite(in1, LOW);
    digitalWrite(in2, HIGH);
  } else {
    digitalWrite(in1, LOW);
    digitalWrite(in2, LOW);
  }
  analogWrite(pwmPin, abs(value));
}

// Drive both sides of the robot together.
void drive(int left, int right) {
  driveOneMotor(LEFT_IN1, LEFT_IN2, LEFT_PWM, left);
  driveOneMotor(RIGHT_IN1, RIGHT_IN2, RIGHT_PWM, right);
}

void stopMotors() {
  drive(0, 0);
  lastMovementAt = 0;
}

int percentToPwm(int percent) {
  return map(constrain(percent, 0, 100), 0, 100, 0, 255);
}

// Turn commands from the app into motor movement.
void handleCommand(String command) {
  command.trim();
  if (command.length() == 0) return;

  if (command == "S") {
    stopMotors();
    return;
  }

  if (command.startsWith("V:")) {
    maximumSpeed = constrain(command.substring(2).toInt(), 0, 100);
    return;
  }

  if (command.startsWith("M:")) {
    int firstComma = command.indexOf(',', 2);
    int secondComma = command.indexOf(',', firstComma + 1);
    if (firstComma < 0 || secondComma < 0) return;

    int x = constrain(command.substring(2, firstComma).toInt(), -100, 100);
    int y = constrain(command.substring(firstComma + 1, secondComma).toInt(), -100, 100);
    int speedLimit = constrain(command.substring(secondComma + 1).toInt(), 0, maximumSpeed);
    int limitPwm = percentToPwm(speedLimit);
    int leftPwm = map(constrain(y + x, -100, 100), -100, 100, -limitPwm, limitPwm);
    int rightPwm = map(constrain(y - x, -100, 100), -100, 100, -limitPwm, limitPwm);

    drive(leftPwm, rightPwm);
    lastMovementAt = millis();
    return;
  }

  int colon = command.indexOf(':');
  String action = colon < 0 ? command : command.substring(0, colon);
  int requestedSpeed = colon < 0 ? maximumSpeed : command.substring(colon + 1).toInt();
  int pwm = percentToPwm(constrain(requestedSpeed, 0, maximumSpeed));

  if (action == "F") drive(pwm, pwm);
  else if (action == "B") drive(-pwm, -pwm);
  else if (action == "L") drive(-pwm, pwm);
  else if (action == "R") drive(pwm, -pwm);
  else return;

  lastMovementAt = millis();
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Bluetooth Classic Serial matches flutter_bluetooth_serial in the app.
  SerialBT.begin("FleXon");

  pinMode(LEFT_IN1, OUTPUT);
  pinMode(LEFT_IN2, OUTPUT);
  pinMode(LEFT_PWM, OUTPUT);
  pinMode(RIGHT_IN1, OUTPUT);
  pinMode(RIGHT_IN2, OUTPUT);
  pinMode(RIGHT_PWM, OUTPUT);
  stopMotors();

  Serial.println("Bluetooth Started");
  Serial.println("Device name: FleXon");
}

void loop() {
  // Keep the original SerialBT receive output and build complete app commands.
  while (SerialBT.available()) {
    char receivedData = SerialBT.read();

    Serial.print("Received: ");
    Serial.println(receivedData);

    if (receivedData == '\n' || receivedData == '\r') {
      if (receivedCommand.length() > 0) {
        handleCommand(receivedCommand);
        receivedCommand = "";
      }
    } else {
      receivedCommand += receivedData;
    }
  }

  // Do not leave the motors running if the connection becomes unresponsive.
  if (lastMovementAt > 0 && millis() - lastMovementAt > COMMAND_TIMEOUT_MS) {
    stopMotors();
  }
  delay(5);
}
