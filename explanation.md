# ESP8266 & Flutter RC App - Architecture & Integration Guide

This document explains exactly how the Flutter application communicates with the ESP8266 RC Car. Use this as your reference manual when modifying, debugging, or rebuilding the firmware for your ESP8266 controller.

---

## 1. Network & Communication Layer
*   **Wi-Fi Mode:** The ESP8266 must act as a Wi-Fi Access Point (AP).
*   **SSID:** `RC_CAR`
*   **IP Address:** The ESP8266 creates the network and defaults to `192.168.4.1`.
*   **Protocol:** WebSocket Server
*   **Port:** `81`
*   **Data Format:** Strict JSON over text payloads.

---

## 2. Inbound to ESP8266 (App -> ESP)
The Flutter app sends 3 types of JSON messages. Your Arduino `webSocketEvent` string parser MUST intercept the `"type"` field to route to the correct logic.

### A. The Control Packet (Drive commands)
The app runs a loop, sending this packet **~30 times per second (30Hz)** whenever the user is driving.
```json
{
  "type": "control",
  "throttle": 75,
  "steering": -30,
  "mode": "drift",
  "maxThrottle": 80,
  "deadzone": 5
}
```
*   `throttle`: Ranges from `-100` (full reverse) to `100` (full forward).
*   `steering`: Ranges from `-100` (full left) to `100` (full right).
*   `mode`: Can be `"normal"`, `"sport"`, `"drift"`, or `"crawl"`.
*   `deadzone`: The joystick deadzone tolerance to ignore tiny thumb twitches (`0` to `20`).

### The Left Slider Bar (`maxThrottle` / Speed Limiter)
The vertical bar on the left side of the app is a **Max Speed Limiter**. 
*   **What it does:** It lets you cap the maximum speed of the car. This is perfect for driving indoors or handing the phone to a beginner. Even if you push the joystick 100% forward, the car will only go as fast as this slider allows.
*   **What it sends:** It sets the `"maxThrottle"` number in the JSON packet (ranging from `10` to `100`).
*   **How the ESP8266 must handle it:** Your ESP8266 code needs to read `doc["maxThrottle"]` and scale the raw throttle line. 
    `int finalThrottle = (throttle * maxThrottle) / 100;`
    *(If you push the joystick all the way up (`throttle=100`), but the left slider is at `50`, the ESP8266 math does `(100 * 50)/100 = 50`. The motor safely tops out at half power.)*

**Your ESP8266 Job (General):** Parse these, apply the deadzone check, scale the throttle down based on `maxThrottle` percentage, shape the curve based on `mode` (e.g., multiply steering by 1.4 for drift), mix differential layout (Left Motor = Throttle + Steering, Right Motor = Throttle - Steering), clamp the final values to -100 to 100, then map to PWM 0-1023 for your L298N pins.

### B. The Emergency Stop Packet (E-Stop)
Fired out-of-band exactly when the user taps the red E-Stop button on the screen.
```json
{
  "type": "estop"
}
```
**Your ESP8266 Job:** Instantly set `throttle = 0`, `steering = 0`, write `LOW` to all IN1/IN2/IN3/IN4 pins, and set `analogWrite(EN, 0)`. 

### C. The Ping Packet (Latency Tracking)
Fired by the app every 1 second continuously to measure network latency.
```json
{
  "type": "ping"
}
```
**Your ESP8266 Job:** Immediately respond with a `"pong"` packet (see Outbound below).

---

## 3. Outbound from ESP8266 (ESP -> App)
The ESP8266 should send 2 types of messages back to the Flutter app.

### A. The Pong Packet
In response to receiving a `"ping"` message.
```json
{
  "type": "pong"
}
```
*Note: The app measures the milliseconds between sending the ping and receiving the pong to display the `ms` lag on the top left of the UI.*

### B. The Status Packet (Live Telemetry)
The ESP8266 should ideally send this packet automatically every 1 second, OR immediately when a client connects, so the app UI knows the car's current state.
```json
{
  "type": "status",
  "throttle": 0,
  "steering": 0,
  "mode": "normal",
  "rssi": -65
}
```
*Note: `rssi` can be read using `WiFi.RSSI()` to show connection strength.*

---

## 4. Hardware Safety & Failsafe Watchdog (Crucial)

**The 400ms Dead-man's Switch**
RC Cars lose Wi-Fi connections easily. If the car is driving at 100% throttle and the Wi-Fi disconnects, the car will keep driving into a wall. 
Because the app guarantees a control packet at 30Hz, the ESP8266 knows it *should* hear from the app every ~33ms. 

In your `loop()` function, you must have a watchdog timer tracking `lastPacketTime`:
```cpp
unsigned long now = millis();
if (now - lastPacketTime > 400) {
  // We haven't heard from the phone in 400ms! Connection is lagging or dead.
  stopCar();
}
```

## Summary Checklist for Firmware Upgrades
If you change the ESP8266 firmware in the future, ensure:
1. `maxThrottle` and `deadzone` from JSON are safely handled.
2. The differential drive mixing (adding throttle + steering) does not overflow your PWM bounds (0-1023). Always pass your mixed data through a final `clamp(-100, 100)` before mapping to PWM.
3. The Failsafe Watchdog is never disabled.
4. The JSON buffer size (`StaticJsonDocument<256>`) is large enough if you add more keys later.