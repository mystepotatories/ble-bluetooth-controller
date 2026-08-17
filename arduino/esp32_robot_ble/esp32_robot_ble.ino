#include <Arduino.h>
#include "BluetoothSerial.h"

BluetoothSerial SerialBT;

// Change these pins to match the robot's motor-driver wiring.
const int LEFT_IN1 = 26;
const int LEFT_IN2 = 27;
const int LEFT_PWM = 25;
const int RIGHT_IN1 = 14;
const int RIGHT_IN2 = 12;
const int RIGHT_PWM = 13;

const unsigned long COMMAND_TIMEOUT_MS = 500;
const unsigned long PACKET_GAP_MS = 20;

String receivedData;
unsigned long lastByteAt = 0;
unsigned long lastCommandAt = 0;
int maximumSpeed = 65;

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

void drive(int left, int right) {
  driveOneMotor(LEFT_IN1, LEFT_IN2, LEFT_PWM, left);
  driveOneMotor(RIGHT_IN1, RIGHT_IN2, RIGHT_PWM, right);
}

void stopMotors() {
  drive(0, 0);
}

int percentToPwm(int percent) {
  return map(constrain(percent, 0, 100), 0, 100, 0, 255);
}

void handleCommand(String command) {
  command.trim();
  if (command.length() == 0) return;

  lastCommandAt = millis();
  Serial.print("Received: ");
  Serial.println(command);

  // Stop control: immediately stop both motors.
  if (command == "S") {
    stopMotors();
    return;
  }

  // Speed control: save the maximum motor speed from V:0 to V:100.
  if (command.startsWith("V:")) {
    maximumSpeed = constrain(command.substring(2).toInt(), 0, 100);
    return;
  }

  // Analog control: mix steering and throttle from M:x,y,speed.
  if (command.startsWith("M:")) {
    int firstComma = command.indexOf(',', 2);
    int secondComma = command.indexOf(',', firstComma + 1);
    if (firstComma < 0 || secondComma < 0) return;

    int x = constrain(command.substring(2, firstComma).toInt(), -100, 100);
    int y = constrain(command.substring(firstComma + 1, secondComma).toInt(), -100, 100);
    int speedLimit = constrain(command.substring(secondComma + 1).toInt(), 0, 100);
    int limitPwm = percentToPwm(speedLimit);
    int leftPwm = map(constrain(y + x, -100, 100), -100, 100, -limitPwm, limitPwm);
    int rightPwm = map(constrain(y - x, -100, 100), -100, 100, -limitPwm, limitPwm);
    drive(leftPwm, rightPwm);
    return;
  }

  int colon = command.indexOf(':');
  String action = colon < 0 ? command : command.substring(0, colon);
  int requestedSpeed = colon < 0 ? maximumSpeed : command.substring(colon + 1).toInt();
  int pwm = percentToPwm(constrain(requestedSpeed, 0, maximumSpeed));

  // Move forward control: run both motors forward.
  if (action == "F") drive(pwm, pwm);
  // Move backward control: run both motors backward.
  else if (action == "B") drive(-pwm, -pwm);
  // Turn left control: reverse left motor and advance right motor.
  else if (action == "L") drive(-pwm, pwm);
  // Turn right control: advance left motor and reverse right motor.
  else if (action == "R") drive(pwm, -pwm);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Motor setup: configure the motor-driver pins as outputs.
  pinMode(LEFT_IN1, OUTPUT);
  pinMode(LEFT_IN2, OUTPUT);
  pinMode(LEFT_PWM, OUTPUT);
  pinMode(RIGHT_IN1, OUTPUT);
  pinMode(RIGHT_IN2, OUTPUT);
  pinMode(RIGHT_PWM, OUTPUT);
  stopMotors();

  // Bluetooth setup: expose the robot as FleXon using Classic Bluetooth SPP.
  SerialBT.begin("FleXon");

  Serial.println("Bluetooth Started");
  Serial.println("Device name: FleXon");
}

void loop() {
  while (SerialBT.available()) {
    char nextCharacter = SerialBT.read();
    if (nextCharacter == '\n' || nextCharacter == '\r') {
      handleCommand(receivedData);
      receivedData = "";
    } else {
      receivedData += nextCharacter;
      lastByteAt = millis();
    }
  }

  // The app does not append a newline, so process after a short packet gap.
  if (receivedData.length() > 0 && millis() - lastByteAt >= PACKET_GAP_MS) {
    handleCommand(receivedData);
    receivedData = "";
  }

  // Stop automatically if the command stream is interrupted.
  if (lastCommandAt > 0 && millis() - lastCommandAt > COMMAND_TIMEOUT_MS) {
    stopMotors();
  }

  delay(5);
}
