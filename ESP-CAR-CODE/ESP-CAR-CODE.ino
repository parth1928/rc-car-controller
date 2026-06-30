#include <ESP8266WiFi.h>
#include <ESP8266mDNS.h>
#include <WebSocketsServer.h>

// --- Configuration ---
// Set this to the phone hotspot SSID.
// The ESP joins the hotspot as a Wi-Fi client and exposes a WebSocket server.
const char* ssid = "GTMS-TELEMETRY";
// Set a password here if the hotspot is secured.
const char* password = "";
const char* mdnsName = "esp8266";

// WebSocket server port
const uint16_t WS_PORT = 81;
WebSocketsServer webSocket = WebSocketsServer(WS_PORT);
bool mdnsActive = false;

// Telemetry send interval in milliseconds
const unsigned long SEND_INTERVAL_MS = 200; // 5 Hz
unsigned long lastSend = 0;

// Helpers
void seedRandom() {
  randomSeed(ESP.getChipId() ^ analogRead(A0));
}

String formatFloat(double v, uint8_t decimals = 2) {
  return String(v, decimals);
}

void updateMdns() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!mdnsActive) {
      if (!MDNS.begin(mdnsName)) {
        Serial.println("mDNS start failed");
      } else {
        MDNS.addService("ws", "tcp", WS_PORT);
        mdnsActive = true;
        Serial.printf("mDNS hostname: %s.local\n", mdnsName);
      }
    } else {
      MDNS.update();
    }
  }
}

void webSocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED: {
      IPAddress ip = webSocket.remoteIP(num);
      Serial.printf("Client %u connected from %s\n", num, ip.toString().c_str());
      break;
    }
    case WStype_DISCONNECTED: {
      Serial.printf("Client %u disconnected\n", num);
      break;
    }
    case WStype_TEXT: {
      Serial.printf("Received from %u: %s\n", num, payload);
      break;
    }
    default:
      break;
  }
}

bool connectToWiFi(unsigned long timeoutMs = 20000) {
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true); // Clear previous
  delay(100);

  if (strlen(password) == 0) {
    Serial.printf("Connecting to open SSID: %s\n", ssid);
    WiFi.begin(ssid);
  } else {
    Serial.printf("Connecting to SSID: %s (with password)\n", ssid);
    WiFi.begin(ssid, password);
  }

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < timeoutMs) {
    delay(250);
    Serial.print('.');
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("Connected to WiFi. IP: ");
    Serial.println(WiFi.localIP());
    return true;
  } else {
    Serial.println("WiFi connection failed or timed out.");
    return false;
  }
}

float sinf_time(float freq = 1.0f, float amplitude = 1.0f) {
  float t = millis() / 1000.0f;
  return sin(t * 2.0f * PI * freq) * amplitude;
}

void sendTelemetry() {
  // Simulate RPM (1500-8000)
  float rpmBase = 4750.0;
  float rpm = rpmBase + sinf_time(0.12f, 3000.0f) + random(-150, 150);

  // Coolant temperature (75-105 C)
  float coolant = 88.0 + sinf_time(0.05f, 10.0f) + random(-3, 3);

  // Intake temp (30-60 C)
  float intakeTemp = 38.0 + sinf_time(0.08f, 8.0f) + random(-2, 2);

  // Intake pressure (kPa) (80-110)
  float intakePressure = 95.0 + sinf_time(0.07f, 12.0f) + random(-3, 3);

  // Battery voltage (13.2-14.0 V)
  float battery = 13.6 + sinf_time(0.03f, 0.3f) + (random(-20, 20) / 100.0);

  // Gear cycles 1..6 every ~6s
  int gear = ((int)(millis() / 6000)) % 6 + 1;

  String json = "{";
  json += "\"rpm\":" + String((int)rpm) + ",";
  json += "\"coolant_temp\":" + formatFloat(coolant, 1) + ",";
  json += "\"intake_temp\":" + formatFloat(intakeTemp, 1) + ",";
  json += "\"intake_pressure\":" + formatFloat(intakePressure, 1) + ",";
  json += "\"battery_voltage\":" + formatFloat(battery, 2) + ",";
  json += "\"speed\":" + formatFloat(0.0, 1) + ",";
  json += "\"tps\":" + formatFloat(0.0, 1) + ",";
  json += "\"lambda\":" + formatFloat(0.0, 2) + ",";
  json += "\"oil_temp\":" + formatFloat(0.0, 1) + ",";
  json += "\"oil_press\":" + formatFloat(0.0, 1) + ",";
  json += "\"fuel_press\":" + formatFloat(0.0, 1) + ",";
  json += "\"engine_runtime\":" + String((unsigned long)(millis() / 1000UL)) + ",";
  json += "\"gear\":" + String(gear);
  json += "}";

  webSocket.broadcastTXT(json);
  Serial.println("Broadcast: " + json);
}

void setup() {
  Serial.begin(115200);
  Serial.println();
  Serial.println("ESP8266 Telemetry (STA mode) starting...");

  seedRandom();

  bool wifiOk = connectToWiFi(20000);
  if (!wifiOk) {
    Serial.println("Unable to join hotspot 'GTMS-TELEMETRY'. Ensure your phone hotspot is active and SSID is correct.");
    // Continue anyway; WebSocket server will still start and accept local connections if network becomes available.
  }

  // Start WebSocket server and attach event handler
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);

  updateMdns();

  Serial.printf("WebSocket server started on port %d\n", WS_PORT);
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("Connect your app to ws://%s:%d\n", WiFi.localIP().toString().c_str(), WS_PORT);
    Serial.printf("Or try ws://%s.local:%d\n", mdnsName, WS_PORT);
  } else {
    Serial.println("Not connected to WiFi yet; connect phone hotspot and retry.");
  }
}

void loop() {
  webSocket.loop();

  // If WiFi disconnected, attempt reconnect periodically
  static unsigned long lastWifiRetry = 0;
  if (WiFi.status() != WL_CONNECTED && millis() - lastWifiRetry > 5000) {
    lastWifiRetry = millis();
    Serial.println("WiFi lost; attempting reconnect...");
    connectToWiFi(10000);
    if (WiFi.status() == WL_CONNECTED) {
      updateMdns();
    }
  }

  unsigned long now = millis();
  if (now - lastSend >= SEND_INTERVAL_MS) {
    lastSend = now;
    sendTelemetry();
  }
}
