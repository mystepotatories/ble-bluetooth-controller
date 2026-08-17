#include <Arduino.h>
// The FleXon app uses BLE, so the old Bluetooth Serial code is commented
// #include "BluetoothSerial.h"
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <esp_system.h>

// BluetoothSerial SerialBT;

// Change if the FleXon motor-driver wiring is different.
const int LEFT_IN1 = 26;
const int LEFT_IN2 = 27;
const int LEFT_PWM = 25;
const int RIGHT_IN1 = 14;
const int RIGHT_IN2 = 12;
const int RIGHT_PWM = 13;

// Stop the robot if movement commands stop arriving from the app.
const unsigned long COMMAND_TIMEOUT_MS = 500;

bool deviceConnected = false;
unsigned long lastMovementAt = 0;
int maximumSpeed = 65;

// Make a fresh BLE UUID; the app discovers it automatically.
String makeUuid() {
  char uuid[37];
  uint32_t first = esp_random();
  uint16_t second = esp_random();
  uint16_t third = (esp_random() & 0x0FFF) | 0x4000;
  uint16_t fourth = (esp_random() & 0x3FFF) | 0x8000;
  uint16_t fifth = esp_random();
  uint32_t last = esp_random();

  snprintf(
    uuid,
    sizeof(uuid),
    "%08lx-%04x-%04x-%04x-%04x%08lx",
    (unsigned long)first,
    second,
    third,
    fourth,
    fifth,
    (unsigned long)last
  );
  return String(uuid);
}

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

// Receive each movement command written by the app.
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    std::string value = characteristic->getValue();
    if (value.empty()) return;

    // BLE replacement for the old SerialBT receive output.
    for (char receivedData : value) {
      Serial.print("Received: ");
      Serial.println(receivedData);
    }

    handleCommand(String(value.c_str()));
  }
};

// Stop the robot safely when the app disconnects.
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    deviceConnected = true;
    Serial.println("App connected");
  }

  void onDisconnect(BLEServer *server) override {
    deviceConnected = false;
    stopMotors();
    BLEDevice::startAdvertising();
    Serial.println("App disconnected; advertising restarted");
  }
};

void setup() {
  Serial.begin(115200);
  delay(1000);

  // SerialBT.begin("FleXon");

  pinMode(LEFT_IN1, OUTPUT);
  pinMode(LEFT_IN2, OUTPUT);
  pinMode(LEFT_PWM, OUTPUT);
  pinMode(RIGHT_IN1, OUTPUT);
  pinMode(RIGHT_IN2, OUTPUT);
  pinMode(RIGHT_PWM, OUTPUT);
  stopMotors();

  // BLE connection to the FleXon app.
  BLEDevice::init("FleXon");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  String serviceUuid = makeUuid();
  String commandUuid = makeUuid();
  BLEService *service = server->createService(serviceUuid.c_str());
  BLECharacteristic *commandCharacteristic = service->createCharacteristic(
    commandUuid.c_str(),
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  commandCharacteristic->setCallbacks(new CommandCallbacks());
  commandCharacteristic->addDescriptor(new BLE2902());
  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(serviceUuid.c_str());
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("Bluetooth Started");
  Serial.println("Device name: FleXon");
}

void loop() {
  // Original Classic receiver
  // if (SerialBT.available()) {
  //   char receivedData = SerialBT.read();
  //
  //   Serial.print("Received: ");
  //   Serial.println(receivedData);
  // }

  // not leave the motors running if the connection becomes unresponsive.
  if (lastMovementAt > 0 && millis() - lastMovementAt > COMMAND_TIMEOUT_MS) {
    stopMotors();
  }
  delay(5);
}
