// Smart Laboratory Safety Monitoring System
// DFI20443 Assessment 3 - ESP32 firmware
// Stage 2: sensors, actuators, local safety logic + WiFi + Firebase (REST API)

#include <DHT.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include "secrets.h"

// ---------- Pins ----------
const int PIN_DHT    = 4;
const int PIN_MQ2    = 34;   // via 3k+3k / 12k divider
const int PIN_TRIG   = 32;
const int PIN_ECHO   = 33;   // via 1k / 2k divider
const int PIN_RELAY  = 26;   // relay switches the buzzer, active-LOW
const int PIN_GREEN  = 18;
const int PIN_YELLOW = 19;
const int PIN_WHITE  = 23;

// ---------- Thresholds (local defaults, later synced from Firebase) ----------
float tempWarn   = 32.0;
float tempDanger = 40.0;
int   gasWarn    = 1500;   // raw ADC 0-4095, calibrate after warm-up
int   gasDanger  = 2500;
float presenceCm = 80.0;   // closer than this = person present

// ---------- Timing ----------
const unsigned long SENSOR_INTERVAL  = 2000;    // DHT22 can't read faster than ~2s
const unsigned long STROBE_INTERVAL  = 120;     // white LED blink speed in danger
const unsigned long MQ2_WARMUP       = 60000;   // ignore gas for the first 60s
const unsigned long LIVE_INTERVAL    = 5000;    // push live data to Firebase
const unsigned long HISTORY_INTERVAL = 30000;   // save a history point
const unsigned long WIFI_RETRY       = 10000;
const unsigned long AUTH_RETRY       = 15000;
const unsigned long ALERT_RETRY      = 3000;
const unsigned long TOKEN_LIFETIME   = 55UL * 60UL * 1000UL;  // Firebase tokens last 60 min

DHT dht(PIN_DHT, DHT22);

enum LabStatus { SAFE, WARNING, DANGER };
LabStatus status     = SAFE;
LabStatus prevStatus = SAFE;
char statusReason[64] = "Normal";

float temperature   = NAN;
float humidity      = NAN;
int   gasLevel      = 0;
float distanceCm    = -1;
bool  personPresent = false;

unsigned long lastSensorRead = 0;
unsigned long lastStrobe     = 0;
bool strobeOn = false;

// What the outputs are actually doing right now (reported to the app)
bool outGreen = false, outYellow = false, outWhite = false, outBuzzer = false;

// ---------- Manual test mode (Serial commands) ----------
bool manualMode = false;
bool manGreen = false, manYellow = false, manWhite = false, manBuzzer = false;

// ---------- Network state ----------
WiFiClientSecure tls;
String idToken;
unsigned long tokenTime       = 0;
unsigned long lastAuthAttempt = 0;
unsigned long lastWifiRetry   = 0;
unsigned long lastLivePush    = 0;
unsigned long lastHistoryPush = 0;
unsigned long lastAlertTry    = 0;
bool alertPending = false;

// ---------- Actuators ----------
void setBuzzer(bool on) {
  digitalWrite(PIN_RELAY, on ? LOW : HIGH);   // active-LOW relay
}

// ---------- Sensors ----------
float readDistanceCm() {
  digitalWrite(PIN_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);

  unsigned long us = pulseIn(PIN_ECHO, HIGH, 30000);  // 30ms timeout
  if (us == 0) return -1;                              // no echo or no sensor
  return us * 0.0343 / 2.0;                            // speed of sound, there and back
}

void readSensors() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (!isnan(t) && !isnan(h)) {
    temperature = t;
    humidity = h;
  } else {
    Serial.println("[DHT22] read failed, keeping last value");
  }

  gasLevel      = analogRead(PIN_MQ2);
  distanceCm    = readDistanceCm();
  personPresent = (distanceCm > 0 && distanceCm < presenceCm);
}

// ---------- Safety logic ----------
LabStatus evaluate() {
  bool gasReady = millis() > MQ2_WARMUP;

  bool tempDng = !isnan(temperature) && temperature >= tempDanger;
  bool tempWrn = !isnan(temperature) && temperature >= tempWarn;
  bool gasDng  = gasReady && gasLevel >= gasDanger;
  bool gasWrn  = gasReady && gasLevel >= gasWarn;

  if (tempDng) {
    snprintf(statusReason, sizeof(statusReason), "High temperature %.1f C", temperature);
    return DANGER;
  }
  if (gasDng) {
    snprintf(statusReason, sizeof(statusReason), "High gas level %d", gasLevel);
    return DANGER;
  }
  if (gasWrn && personPresent) {
    snprintf(statusReason, sizeof(statusReason), "Gas %d with person nearby", gasLevel);
    return DANGER;
  }
  if (tempWrn) {
    snprintf(statusReason, sizeof(statusReason), "Temperature rising %.1f C", temperature);
    return WARNING;
  }
  if (gasWrn) {
    snprintf(statusReason, sizeof(statusReason), "Gas level rising %d", gasLevel);
    return WARNING;
  }
  snprintf(statusReason, sizeof(statusReason), "Normal");
  return SAFE;
}

void applyOutputs() {
  outGreen  = (status == SAFE);
  outYellow = (status == WARNING);
  outBuzzer = (status == DANGER);
  outWhite  = (status == DANGER);   // strobing

  digitalWrite(PIN_GREEN,  outGreen);
  digitalWrite(PIN_YELLOW, outYellow);
  setBuzzer(outBuzzer);

  if (status != DANGER) {
    strobeOn = false;
    digitalWrite(PIN_WHITE, LOW);
  }
}

void updateStrobe() {
  if (manualMode || status != DANGER) return;
  if (millis() - lastStrobe >= STROBE_INTERVAL) {
    lastStrobe = millis();
    strobeOn = !strobeOn;
    digitalWrite(PIN_WHITE, strobeOn);
  }
}

// ---------- Names ----------
const char* statusName(LabStatus s) {
  switch (s) {
    case SAFE:    return "SAFE";
    case WARNING: return "WARNING";
    default:      return "DANGER";
  }
}

const char* statusKey(LabStatus s) {   // lowercase for Firebase / the app
  switch (s) {
    case SAFE:    return "safe";
    case WARNING: return "warning";
    default:      return "danger";
  }
}

const char* onOff(bool v) { return v ? "ON" : "OFF"; }

// ---------- WiFi ----------
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WIFI] Connecting to " WIFI_SSID);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 10000) {
    delay(250);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf(" connected, IP %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println(" failed. Running offline, will keep retrying.");
  }
}

void maintainWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  if (millis() - lastWifiRetry < WIFI_RETRY) return;
  lastWifiRetry = millis();
  Serial.println("[WIFI] Disconnected, reconnecting...");
  WiFi.reconnect();
}

// ---------- HTTPS helper ----------
int httpRequest(const char* method, const String& url, const String& body, String* response = nullptr) {
  HTTPClient http;
  http.setTimeout(5000);
  if (!http.begin(tls, url)) return -1;
  http.addHeader("Content-Type", "application/json");

  int code = http.sendRequest(method, body);
  if (response) *response = http.getString();
  http.end();
  return code;
}

// ---------- Firebase Auth ----------
bool firebaseSignIn() {
  lastAuthAttempt = millis();

  JsonDocument req;
  req["email"]             = DEVICE_EMAIL;
  req["password"]          = DEVICE_PASSWORD;
  req["returnSecureToken"] = true;
  String body;
  serializeJson(req, body);

  String resp;
  String url = String("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=") + FIREBASE_API_KEY;
  int code = httpRequest("POST", url, body, &resp);

  if (code != 200) {
    Serial.printf("[AUTH] Sign-in failed (%d): %s\n", code, resp.c_str());
    idToken = "";
    return false;
  }

  JsonDocument doc;
  if (deserializeJson(doc, resp)) {
    Serial.println("[AUTH] Could not read sign-in response");
    return false;
  }

  idToken   = doc["idToken"].as<String>();
  tokenTime = millis();
  Serial.println("[AUTH] Signed in as " DEVICE_EMAIL);
  return true;
}

bool ensureAuth() {
  bool expired = idToken.length() == 0 || millis() - tokenTime > TOKEN_LIFETIME;
  if (!expired) return true;
  if (lastAuthAttempt != 0 && millis() - lastAuthAttempt < AUTH_RETRY) return false;
  return firebaseSignIn();
}

// ---------- Realtime Database ----------
bool dbRequest(const char* method, const char* path, JsonDocument& doc) {
  String body;
  serializeJson(doc, body);

  // print=silent: Firebase replies with an empty 204 instead of echoing the data back
  String url = String(FIREBASE_DB_URL) + path + ".json?print=silent&auth=" + idToken;
  int code = httpRequest(method, url, body);

  if (code == 200 || code == 204) return true;

  Serial.printf("[DB] %s %s failed (%d)\n", method, path, code);
  if (code == 401) idToken = "";   // token rejected, sign in again next time
  return false;
}

void pushLive() {
  JsonDocument doc;

  JsonObject live = doc["live"].to<JsonObject>();
  if (!isnan(temperature)) {
    live["temp"]     = serialized(String(temperature, 1));
    live["humidity"] = serialized(String(humidity, 1));
  }
  live["gas"]           = gasLevel;
  live["gasReady"]      = millis() > MQ2_WARMUP;
  live["distance"]      = serialized(String(distanceCm, 0));   // -1 = no reading
  live["personPresent"] = personPresent;
  live["status"]        = statusKey(status);
  live["reason"]        = statusReason;
  live["mode"]          = manualMode ? "manual" : "auto";
  live["timestamp"][".sv"] = "timestamp";   // Firebase fills in its own server time

  JsonObject outputs = live["outputs"].to<JsonObject>();
  outputs["green"]  = outGreen;
  outputs["yellow"] = outYellow;
  outputs["white"]  = outWhite;
  outputs["buzzer"] = outBuzzer;

  // Keys with "/" update deeper paths in the same request
  doc["device/lastSeen"][".sv"] = "timestamp";
  doc["device/rssi"]            = WiFi.RSSI();
  doc["device/ip"]              = WiFi.localIP().toString();

  dbRequest("PATCH", "/lab", doc);
}

void pushHistory() {
  JsonDocument doc;
  if (!isnan(temperature)) {
    doc["temp"]     = serialized(String(temperature, 1));
    doc["humidity"] = serialized(String(humidity, 1));
  }
  doc["gas"]      = gasLevel;
  doc["distance"] = serialized(String(distanceCm, 0));
  doc["status"]   = statusKey(status);
  doc["timestamp"][".sv"] = "timestamp";

  dbRequest("POST", "/lab/history", doc);   // POST = new entry with a unique key
}

void pushAlert() {
  JsonDocument doc;
  doc["status"] = statusKey(status);
  doc["reason"] = statusReason;
  if (!isnan(temperature)) doc["temp"] = serialized(String(temperature, 1));
  doc["gas"]    = gasLevel;
  doc["timestamp"][".sv"] = "timestamp";

  if (dbRequest("POST", "/lab/alerts", doc)) {
    alertPending = false;
    Serial.printf("[ALERT] Logged: %s (%s)\n", statusName(status), statusReason);
  }
}

// ---------- Config pulled from Firebase ----------
const unsigned long CONFIG_INTERVAL = 2000;
unsigned long lastConfigPull = 0;

// Same shape as dbRequest(), but reads instead of writes
bool dbGet(const char* path, JsonDocument& doc) {
  String url = String(FIREBASE_DB_URL) + path + ".json?auth=" + idToken;
  String resp;
  int code = httpRequest("GET", url, "", &resp);
  if (code != 200) {
    Serial.printf("[DB] GET %s failed (%d)\n", path, code);
    if (code == 401) idToken = "";   // token rejected, sign in again next time
    return false;
  }
  return !deserializeJson(doc, resp);
}

// Thresholds and output requests both live in the database, so the app can
// change either one without a reflash.
void pullConfig() {
  JsonDocument th;
  if (dbGet("/lab/thresholds", th)) {
    tempWarn   = th["tempWarn"]   | tempWarn;
    tempDanger = th["tempDanger"] | tempDanger;
    gasWarn    = th["gasWarn"]    | gasWarn;
    gasDanger  = th["gasDanger"]  | gasDanger;
    presenceCm = th["presenceCm"] | presenceCm;
  }

  JsonDocument act;
  if (!dbGet("/lab/actuators", act)) return;

  const char* want = act["mode"] | "auto";

  // The app hands the outputs back by writing mode: "auto".
  if (strcmp(want, "manual") != 0) {
    if (manualMode) {
      manualMode = false;
      Serial.println("Mode: AUTO (from app)");
      applyOutputs();
      lastLivePush = 0;   // report it now instead of up to LIVE_INTERVAL later
    }
    return;
  }

  // Taking over zeroes the outputs, so apply the app's values straight after.
  bool justEntered = false;
  if (!manualMode) {
    enterManual();
    justEntered = true;
  }

  bool g = act["green"]  | manGreen;
  bool y = act["yellow"] | manYellow;
  bool w = act["white"]  | manWhite;
  bool b = act["buzzer"] | manBuzzer;

  if (justEntered || g != manGreen || y != manYellow ||
      w != manWhite || b != manBuzzer) {
    manGreen  = g;
    manYellow = y;
    manWhite  = w;
    manBuzzer = b;
    applyManual();
  }
}

void syncFirebase() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (!ensureAuth()) return;

  if (millis() - lastConfigPull >= CONFIG_INTERVAL) {
    lastConfigPull = millis();
    pullConfig();
  }

  if (alertPending && millis() - lastAlertTry >= ALERT_RETRY) {
    lastAlertTry = millis();
    pushAlert();
  }
  if (millis() - lastLivePush >= LIVE_INTERVAL) {
    lastLivePush = millis();
    pushLive();
  }
  if (millis() - lastHistoryPush >= HISTORY_INTERVAL) {
    lastHistoryPush = millis();
    pushHistory();
  }
}

// ---------- Manual test mode ----------
void printHelp() {
  Serial.println("Commands:");
  Serial.println("  1 = toggle green LED");
  Serial.println("  2 = toggle yellow LED");
  Serial.println("  3 = toggle white LED");
  Serial.println("  4 = toggle buzzer (relay)");
  Serial.println("  0 = all OFF");
  Serial.println("  a = back to AUTO mode");
  Serial.println("  n = network status");
  Serial.println("  h = show this help");
}

void printNetwork() {
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[NET] WiFi OK | IP %s | RSSI %d dBm | Firebase %s\n",
                  WiFi.localIP().toString().c_str(), WiFi.RSSI(),
                  idToken.length() ? "signed in" : "not signed in");
  } else {
    Serial.println("[NET] WiFi not connected");
  }
}

void enterManual() {
  if (manualMode) return;
  manualMode = true;
  manGreen = manYellow = manWhite = manBuzzer = false;   // start clean
  Serial.println("Mode: MANUAL (type a for AUTO)");
}

void applyManual() {
  outGreen  = manGreen;
  outYellow = manYellow;
  outWhite  = manWhite;
  outBuzzer = manBuzzer;

  digitalWrite(PIN_GREEN,  manGreen);
  digitalWrite(PIN_YELLOW, manYellow);
  digitalWrite(PIN_WHITE,  manWhite);
  setBuzzer(manBuzzer);
  Serial.printf("Manual -> Green: %s | Yellow: %s | White: %s | Buzzer: %s\n",
                onOff(manGreen), onOff(manYellow), onOff(manWhite), onOff(manBuzzer));
}

void handleSerial() {
  while (Serial.available()) {
    char c = Serial.read();
    switch (c) {
      case '1': enterManual(); manGreen  = !manGreen;  break;
      case '2': enterManual(); manYellow = !manYellow; break;
      case '3': enterManual(); manWhite  = !manWhite;  break;
      case '4': enterManual(); manBuzzer = !manBuzzer; break;
      case '0': enterManual(); manGreen = manYellow = manWhite = manBuzzer = false; break;
      case 'a':
      case 'A':
        manualMode = false;
        Serial.println("Mode: AUTO");
        applyOutputs();
        continue;
      case 'n':
      case 'N':
        printNetwork();
        continue;
      case 'h':
      case 'H':
        printHelp();
        continue;
      case '\n':
      case '\r':
      case ' ':
        continue;                 // ignore line endings from Serial Monitor
      default:
        Serial.printf("Unknown command '%c', type h for help\n", c);
        continue;
    }
    applyManual();
  }
}

// ---------- Serial output ----------
void printReadings() {
  Serial.printf("T: %.1f C | H: %.1f %% | Gas: %d%s | Dist: %.0f cm%s | %s | %s\n",
                temperature, humidity,
                gasLevel, millis() > MQ2_WARMUP ? "" : " (warming up)",
                distanceCm, personPresent ? " (person)" : "",
                statusName(status),
                manualMode ? "MANUAL" : "AUTO");
}

// ---------- Main ----------
void setup() {
  pinMode(PIN_RELAY, OUTPUT);
  setBuzzer(false);              // first thing: make sure the alarm is OFF

  Serial.begin(115200);

  pinMode(PIN_GREEN,  OUTPUT);
  pinMode(PIN_YELLOW, OUTPUT);
  pinMode(PIN_WHITE,  OUTPUT);
  pinMode(PIN_TRIG,   OUTPUT);
  pinMode(PIN_ECHO,   INPUT);

  dht.begin();

  // Lamp test: each LED lights once so you can see they all work
  int leds[] = { PIN_GREEN, PIN_YELLOW, PIN_WHITE };
  for (int pin : leds) {
    digitalWrite(pin, HIGH);
    delay(300);
    digitalWrite(pin, LOW);
  }

  Serial.println("Lab Safety Monitor started. MQ-2 warming up for 60s...");
  printHelp();

  tls.setInsecure();   // skips certificate check, see notes
  connectWiFi();
}

void loop() {
  handleSerial();

  // 1. Safety first: sensors and outputs never wait for the network
  if (millis() - lastSensorRead >= SENSOR_INTERVAL) {
    lastSensorRead = millis();
    readSensors();
    status = evaluate();

    // App control is absolute by request: a DANGER no longer reclaims the
    // outputs, so an override holds until the app writes mode: "auto".

    if (status != prevStatus) {
      Serial.printf("[EVENT] %s -> %s: %s\n", statusName(prevStatus), statusName(status), statusReason);
      prevStatus   = status;
      alertPending = true;
    }

    if (!manualMode) applyOutputs();
    printReadings();
  }
  updateStrobe();

  // 2. Then the network
  maintainWiFi();
  syncFirebase();
}
