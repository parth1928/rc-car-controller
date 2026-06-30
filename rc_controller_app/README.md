# RC Controller

> Real-time UDP RC car controller for ESP8266 + L298N — with 3 control layouts, 4 drive modes, and live telemetry.

Turn your phone into a **high-performance RC car remote**. This Flutter app communicates over UDP with an ESP8266-equipped car, delivering low-latency control, adaptive packet timing, and a dark neon gaming UI.

---

## Features

### Controls
- **3 Input Layouts** — Floating Joysticks (dual-stick), D-Pad (discrete 8-way), Retro Gamepad (Nintendo-style)
- **4 Drive Modes** — Normal (cyan), Sport (red), Drift (purple), Crawl (green) — each with its own neon accent
- **Max Speed Limiter** — Vertical slider caps throttle percentage; perfect for beginners or indoor driving
- **Steering Sensitivity** — Adjustable 20–100% steering response curve
- **Joystick Deadzone** — 0–20% configurable threshold to filter noise
- **Cruise Control** — Hold current throttle, toggle on/off
- **360° Tank Spin** — Hold-to-spin button, full rotation on the spot
- **Emergency Stop** — Big red E-Stop, kills all motors instantly

### Network
- **UDP Protocol** — Lightweight, connectionless, sub-millisecond overhead
- **Broadcast Discovery** — Auto-finds the ESP on 4 common subnets
- **Adaptive Send Rate** — 14–44 ms intervals based on input intensity (faster when driving hard)
- **Latency Display** — Live ping in ms, send rate in Hz, TX success/fail counters
- **Connection Watchdog** — Auto-reconnect with 300 ms health checks

### UI/UX
- **Full Immersive Landscape** — No status bar, no navigation keys
- **Dark Neon Theme** — Mode-colored accents, glowing joystick shadows
- **Haptic Feedback** — Sharp vibrations on connect, mode change, E-stop, and spin
- **Persistent Settings** — All preferences saved via SharedPreferences

### Hardware (ESP8266 Side)
- WebSocket server broadcasting simulated car telemetry (RPM, coolant temp, battery voltage, gear, etc.)
- mDNS support (`esp8266.local`)
- Auto-reconnect to Wi-Fi hotspot on disconnect
- 5 Hz telemetry broadcast

---

## Architecture

```
┌─────────────────────────┐         UDP          ┌──────────────────────┐
│   Flutter App (Phone)   │ ◄──────────────────► │   ESP8266 (Car)      │
│                         │   C,seq,thr,str,md,   │                      │
│  - UdpControlService    │   maxThr,deadzone     │  - WebSocket Server  │
│  - DriveController      │                       │  - L298N Motor Driver│
│  - Adaptive Send Loop   │   P                   │  - 400ms Watchdog    │
│  - Broadcast Discovery  │   (ping)              │  - Telemetry (5 Hz)  │
│  - 3 Control Layouts    │   H                   │                      │
│  - 4 Drive Modes        │   (hello/discovery)   │                      │
└─────────────────────────┘                       └──────────────────────┘
```

### Packet Format

| Type | Format | Description |
|------|--------|-------------|
| Control | `C,seq,throttle,steering,modeId,maxThrottle,deadzone` | Drive commands at adaptive rate |
| Ping | `P` | Latency measurement (1 Hz) |
| E-Stop | `E` | Kill all motors immediately |
| Discovery | `D` | Broadcast to find car |
| Hello | `H` | Car response to discovery |
| Status | `S,throttle,steering,mode,rssi` | Car telemetry |

---

## Hardware Setup

### Components
- **ESP8266** (NodeMCU / Wemos D1 Mini)
- **L298N** Motor Driver
- **DC Motors** x2 (differential drive)
- **Battery Pack** (7.4V–12V)

### Wiring (ESP8266 → L298N)

| ESP8266 Pin | L298N Pin |
|-------------|-----------|
| D1 (GPIO5)  | IN1       |
| D2 (GPIO4)  | IN2       |
| D3 (GPIO0)  | IN3       |
| D4 (GPIO2)  | IN4       |
| D5 (GPIO14) | ENA (PWM) |
| D6 (GPIO12) | ENB (PWM) |

### Flashing the ESP

1. Open `ESP-CAR-CODE/ESP-CAR-CODE.ino` in Arduino IDE
2. Install libraries: `ESP8266WiFi`, `ESP8266mDNS`, `WebSocketsServer`
3. Set your phone hotspot SSID/password in the code
4. Select board: **NodeMCU 1.0 (ESP-12E)**
5. Upload via USB

---

## Building the App

```bash
cd rc_controller_app

# Get dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK
flutter build apk --release

# Build app bundle (Play Store)
flutter build appbundle --release
```

---

## Development

```bash
# Run tests
flutter test

# Analyze
flutter analyze
```

### Project Structure

```
rc_controller_app/
├── lib/
│   ├── main.dart                  # App entry, landscape lock, immersive mode
│   ├── domain/
│   │   └── models.dart            # ControlPacket, StatusPacket
│   ├── services/
│   │   └── udp_service.dart       # UdpControlService — UDP socket, discovery, ping
│   ├── features/
│   │   └── drive/
│   │       ├── drive_screen.dart   # Main UI: status bar, controls panel, bottom row
│   │       ├── drive_controller.dart # DriveController — adaptive send loop, modes
│   │       ├── gamepad_joystick.dart # FloatingJoystick widget (dual-stick)
│   │       └── control_layouts.dart  # VirtualDPad + GamepadController widgets
│   └── theme/
│       └── app_theme.dart         # Dark theme, neon mode colors
├── ESP-CAR-CODE/
│   └── ESP-CAR-CODE.ino           # ESP8266 firmware (WebSocket server + telemetry)
└── explanation.md                  # Full architecture guide
```

---

## License

MIT
