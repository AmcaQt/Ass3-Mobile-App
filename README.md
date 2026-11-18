# Smart Laboratory Safety Monitoring System

DFI20443 Assessment 3 — an ESP32 watches a lab bench and a Flutter app reports
on it and controls it, with Firebase Realtime Database in between.

The device is the safety authority: it reads its sensors, decides a status and
drives its own alarm every 2 seconds, whether or not the network is up. The app
is a window onto that, plus a remote control for the outputs.

```
ESP32 ──push (REST, every 5s)──> Firebase RTDB ──stream──> Flutter app
      <──poll (every 2s)───────   /lab           <──write──
```

## Hardware

| Part | Pin | Notes |
|---|---|---|
| DHT22 temperature + humidity | GPIO 4 | cannot be read faster than ~2 s |
| MQ-2 gas | GPIO 34 (ADC) | via 3k+3k / 12k divider; 60 s warm-up |
| HC-SR04 ultrasonic | TRIG 32, ECHO 33 | ECHO via 1k / 2k divider |
| Green LED | GPIO 18 | lit while safe |
| Yellow LED | GPIO 19 | lit on a warning |
| White LED | GPIO 23 | strobes at 120 ms in danger |
| Buzzer | GPIO 26 | through a relay, **active-LOW** |

## Safety logic

Evaluated every 2 seconds, worst condition wins:

| Status | Condition |
|---|---|
| `danger` | temp ≥ `tempDanger`, or gas ≥ `gasDanger`, or gas ≥ `gasWarn` **with a person present** |
| `warning` | temp ≥ `tempWarn`, or gas ≥ `gasWarn` |
| `safe` | everything below the warning levels |

Gas is ignored for the first 60 seconds while the MQ-2 heats up; `gasReady`
reports that to the app. "Person present" means the ultrasonic sensor reads
closer than `presenceCm`.

Defaults: `tempWarn` 32 °C, `tempDanger` 40 °C, `gasWarn` 1500, `gasDanger`
2500 (raw ADC), `presenceCm` 80 cm. All five are editable from the app's
Settings tab and are picked up by the device within 2 seconds.

## Database layout

```
/lab
  live        temp, humidity, gas, gasReady, distance, personPresent,
              status, reason, mode, timestamp, outputs{green,yellow,white,buzzer}
  actuators   green, yellow, white, buzzer, mode    <- the app writes here
  thresholds  tempWarn, tempDanger, gasWarn, gasDanger, presenceCm
  device      lastSeen, rssi, ip
  history/<push id>   temp, humidity, gas, distance, status, timestamp
  alerts/<push id>    reason, status, temp, gas, timestamp
```

Two conventions worth knowing:

- **`actuators` is a request, `live/outputs` is the truth.** The app writes the
  former and displays the latter, so a switch can never claim an LED is lit
  when the board says otherwise.
- **`device/online` does not exist.** The firmware uses the REST API and so has
  no `onDisconnect` handler. The app derives "online" from `device/lastSeen`
  being under 15 seconds old.

## Repository layout

```
lib/
  models/      SensorData, AlertEvent — the RTDB contract in Dart
  screens/     dashboard, monitor, control, history, alerts, settings, login
  services/    DbService (every /lab path), AuthService
  theme/
lab_safety_firmware/
  lab_safety_firmware.ino    sensors, safety logic, WiFi, Firebase REST
  secrets.h.example          copy to secrets.h and fill in
test/
  widget_test.dart           app shell and Control tab
  seed_contract_test.dart    seed_full.json still matches the models
seed_full.json               hand-seeded /lab tree for demos without hardware
```

## Setup

### App

```bash
flutter pub get
flutter run
```

Firebase is already configured (`lib/firebase_options.dart`,
`android/app/google-services.json`, project `lab-safety-monitor-8e95c`,
database in `asia-southeast1`).

### Firmware

Copy the template and fill it in — `secrets.h` is gitignored and must never be
committed:

```bash
cp lab_safety_firmware/secrets.h.example lab_safety_firmware/secrets.h
```

Needs the `DHT sensor library` and `ArduinoJson` (v7) libraries, and a device
account that exists under Firebase Authentication → Users.

### Database rules

```json
{
  "rules": {
    "lab": {
      ".read": "auth != null",
      ".write": "auth != null",
      "history": { ".indexOn": "timestamp" },
      "alerts":  { ".indexOn": "timestamp" }
    }
  }
}
```

Every read and write requires a signed-in user, so the app offers email/password
and anonymous guest sign-in, and the firmware signs in over the Identity Toolkit
REST API. The two indexes are required by the app's `orderByChild('timestamp')`
queries.

### Demo without hardware

Import `seed_full.json` at the **root** of the Realtime Database (it already
contains the `lab` wrapper). Note that the Dashboard will correctly show
"Device offline" about 15 seconds later, because seeded data has no heartbeat.

## Tests

```bash
flutter analyze
flutter test
```

## Design decision: app override is absolute

Flipping any switch on the Control tab takes the LEDs and buzzer away from the
safety logic, and **keeps them even during a danger condition**. The usual
interlock — a `DANGER` reclaiming the outputs — was deliberately removed so
that control works under any condition. "Hand back to the device" in the app is
the only way to return the outputs to automatic control.

This is a conscious tradeoff: it means the buzzer will not sound on a real gas
or temperature event while the app is holding the outputs. To restore the
interlock, put this back in `loop()` after `status = evaluate();`:

```c
if (status == DANGER && manualMode) {
  manualMode = false;
  Serial.println("DANGER detected, manual mode cancelled, back to AUTO");
}
```
