#include "ble-provisioning.h"
#include "nvs-config.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- UUIDs (from docs/protocols/ble-provisioning-and-mqtt-auth.md) ---
#define BLE_SERVICE_UUID    "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define UUID_SSID           "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define UUID_PASSWORD       "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define UUID_SERVER_HOST    "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define UUID_STATUS         "beb5483e-36e1-4688-b7f5-ea07361b26ab"
#define UUID_MQTT_USER      "beb5483e-36e1-4688-b7f5-ea07361b26ac"
#define UUID_MQTT_PASSWORD  "beb5483e-36e1-4688-b7f5-ea07361b26ad"
#define UUID_MQTT_SCHEME    "beb5483e-36e1-4688-b7f5-ea07361b26ae"
#define UUID_DEVICE_ID      "beb5483e-36e1-4688-b7f5-ea07361b26af"

static BLEServer*         s_server       = nullptr;
static BLECharacteristic* s_status_char  = nullptr;
// `volatile` — these are written from the BLE FreeRTOS task but polled from the
// main task (loop/setup). Without volatile, the compiler may hoist the read
// out of the wait loop in main.cpp, causing it to spin forever.
static volatile bool      s_prov_done    = false;

// Tracks which of the 6 WRITE chars have been received (see comment above on volatile)
static volatile bool s_got_ssid   = false;
static volatile bool s_got_pass   = false;
static volatile bool s_got_host   = false;
static volatile bool s_got_scheme = false;
static volatile bool s_got_user   = false;
static volatile bool s_got_mpass  = false;

static bool all_received() {
    return s_got_ssid && s_got_pass && s_got_host &&
           s_got_scheme && s_got_user && s_got_mpass;
}

// --- Write callback handler ---

class ProvisionCallback : public BLECharacteristicCallbacks {
public:
    // allow_empty — true for mqtt_user / mqtt_pass (anonymous dev broker).
    // Rejecting empty writes on the other chars prevents accidental or adversarial
    // "satisfied" provisioning with blank WiFi/host values.
    ProvisionCallback(const char* nvs_key, volatile bool* flag, bool allow_empty)
        : _key(nvs_key), _flag(flag), _allow_empty(allow_empty) {}

    void onWrite(BLECharacteristic* c) override {
        String val = c->getValue().c_str();
        if (val.length() == 0 && !_allow_empty) {
            Serial.printf("[BLE] Ignoring empty write for %s\n", _key);
            return;
        }
        Serial.printf("[BLE] Received %s = \"%s\"\n", _key, val.c_str());
        nvs_set(_key, val);
        *_flag = true;

        // Last-write trigger: when all 6 chars received, signal main loop
        if (all_received() && !s_prov_done) {
            s_prov_done = true;
            Serial.println("[BLE] All characteristics received — provisioning complete");
            ble_set_status("connecting");
        }
    }

private:
    const char*    _key;
    volatile bool* _flag;
    bool           _allow_empty;
};

// --- BLE server connection callbacks ---

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer*) override {
        Serial.println("[BLE] Client connected");
    }
    void onDisconnect(BLEServer* srv) override {
        Serial.println("[BLE] Client disconnected — restarting advertising");
        if (!s_prov_done) {
            BLEDevice::startAdvertising();
        }
    }
};

// --- Helper: create a WRITE characteristic ---

static BLECharacteristic* make_write_char(BLEService* svc,
                                          const char* uuid,
                                          BLECharacteristicCallbacks* cb) {
    BLECharacteristic* c = svc->createCharacteristic(
        uuid, BLECharacteristic::PROPERTY_WRITE);
    c->setCallbacks(cb);
    return c;
}

// --- Public API ---

void ble_init(const char* device_id) {
    // Build advertisement name from last 6 chars of device_id
    String dev_id_str(device_id);
    String adv_name = "SleepPad-";
    if (dev_id_str.length() >= 6) {
        adv_name += dev_id_str.substring(dev_id_str.length() - 6);
    } else {
        adv_name += dev_id_str;
    }

    Serial.printf("[BLE] Initialising — advertising as \"%s\"\n", adv_name.c_str());

    BLEDevice::init(adv_name.c_str());
    s_server = BLEDevice::createServer();
    s_server->setCallbacks(new ServerCallbacks());

    BLEService* svc = s_server->createService(BLE_SERVICE_UUID);

    // 6 WRITE characteristics — each persists one NVS key.
    // MQTT user/pass may legitimately be empty (anonymous dev broker); the other
    // four must be non-empty for a working WiFi + MQTT connection.
    make_write_char(svc, UUID_SSID,          new ProvisionCallback(NVS_KEY_SSID,   &s_got_ssid,   /*allow_empty=*/false));
    make_write_char(svc, UUID_PASSWORD,      new ProvisionCallback(NVS_KEY_PASS,   &s_got_pass,   /*allow_empty=*/false));
    make_write_char(svc, UUID_SERVER_HOST,   new ProvisionCallback(NVS_KEY_HOST,   &s_got_host,   /*allow_empty=*/false));
    make_write_char(svc, UUID_MQTT_USER,     new ProvisionCallback(NVS_KEY_USER,   &s_got_user,   /*allow_empty=*/true));
    make_write_char(svc, UUID_MQTT_PASSWORD, new ProvisionCallback(NVS_KEY_MPASS,  &s_got_mpass,  /*allow_empty=*/true));
    make_write_char(svc, UUID_MQTT_SCHEME,   new ProvisionCallback(NVS_KEY_SCHEME, &s_got_scheme, /*allow_empty=*/false));

    // Status READ/NOTIFY characteristic
    s_status_char = svc->createCharacteristic(
        UUID_STATUS,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
    s_status_char->addDescriptor(new BLE2902());
    s_status_char->setValue("waiting");

    // DeviceId READ characteristic — Flutter reads this to confirm device_id
    BLECharacteristic* dev_id_char = svc->createCharacteristic(
        UUID_DEVICE_ID, BLECharacteristic::PROPERTY_READ);
    dev_id_char->setValue(device_id);

    svc->start();

    BLEAdvertising* adv = BLEDevice::getAdvertising();
    adv->addServiceUUID(BLE_SERVICE_UUID);
    adv->setScanResponse(true);
    adv->setMinPreferred(0x06);
    adv->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] Advertising started — waiting for provisioning");
}

void ble_set_status(const char* status) {
    if (!s_status_char) return;
    s_status_char->setValue(status);
    s_status_char->notify();
    Serial.printf("[BLE] Status → %s\n", status);
}

void ble_stop() {
    // Idempotent — safe to call when BLE was never initialised (e.g. when NVS
    // already has WiFi credentials and we skipped provisioning). Without this
    // guard, deinit on an uninitialised stack crashes on reboot.
    if (s_server == nullptr) {
        return;
    }
    Serial.println("[BLE] Stopping BLE stack");
    BLEDevice::stopAdvertising();
    BLEDevice::deinit(true);
    s_server      = nullptr;
    s_status_char = nullptr;
}

bool ble_provisioning_complete() {
    return s_prov_done;
}
