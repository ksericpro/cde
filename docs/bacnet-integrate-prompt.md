# Task: Build CDE BACnet Ingestion & Transformation Adapter (BACnet GW ➔ CDE ➔ IMOPS)

## Context & Architecture

Our deployed **BACnet/IP Edge Gateway (`zaarr-bacnet-gw-01`)** at the **Smart Nation Exhibition System** monitors an Optergy P864 controller (`device_id: 864077` at `192.168.0.160:47808`) with **12 BACnet sensors** (5 wireless environmental points + 7 safety/security dry contacts).

Data flows as:
`BACnet Edge Gateway (HTTPS POST) ➔ CDE API Gateway ➔ [Optional CDE Internal MQ] ➔ CDE Adapter (Massage + Auth) ➔ IMOPS API`

Please implement the CDE side of this pipeline:

1. **CDE API Gateway Ingestion Endpoints** secured with `X-API-Key` to accept batched telemetry and controller status from `zaarr-bacnet-gw-01`.
2. **Internal Queuing / Buffering (if standard in CDE):** Publish inbound batches to CDE's internal queue and return `202 Accepted` (or `200 OK`) immediately so edge requests complete in <50ms, with worker retries if IMOPS is temporarily unreachable.
3. **Payload Transformation ("Massaging"):** Normalize raw BACnet telemetry into IMOPS's clean 12-sensor dashboard schema.
4. **IMOPS Outbound Client:** Authenticate against IMOPS (supporting static API key / Bearer token or cached JWT login refresh on `401`) and `POST` the transformed updates to IMOPS.

---

## 1. Inbound Endpoints on CDE API Gateway (Edge Gateway ➔ CDE)

All requests from `zaarr-bacnet-gw-01` use:

- `Content-Type: application/json`
- `User-Agent: zaarr-bacnet-gw/1.0`
- `X-API-Key: <CDE_API_KEY>`
- Gateway retries automatically with exponential backoff on `HTTP 429` and `5xx`. Return `200 OK` or `202 Accepted` with `{"status": "accepted"}` on success.

### Endpoint A: `POST /api/v1/bacnet/telemetry`

Sent every ~1.5s–5s (5-second poll batches + immediate real-time COV notifications when dry contacts or values change).

```json
{
  "gateway_id": "zaarr-bacnet-gw-01",
  "site_name": "Smart Nation Exhibition System",
  "batch_id": "20261113T012000Z-42",
  "sent_at": "2026-11-13T01:20:00Z",
  "count": 2,
  "readings": [
    {
      "timestamp": "2026-11-13T01:19:59.812Z",
      "source_type": "poll",
      "device_id": 864077,
      "device_name": "P864-864077",
      "controller_model": "P864",
      "device_address": "192.168.0.160:47808",
      "object_type": "analog-input",
      "object_instance": 101,
      "object_id": "analog-input:101",
      "short_object_id": "AI-101",
      "point_name": "BW-INT-M (WIRELESS AIR TOUCH DISPLAY)",
      "property_label": "Temperature",
      "dashboard_label": "BW-INT-M",
      "connection_bus": "BG-1000-M (Wireless)",
      "value": 23.45,
      "value_text": "23.45 °C",
      "unit": "°C",
      "unit_id": 62,
      "is_triggered": false,
      "is_alarm": false,
      "quality": "good",
      "status_flags": {
        "in_alarm": false,
        "fault": false,
        "overridden": false,
        "out_of_service": false
      }
    },
    {
      "timestamp": "2026-11-13T01:19:59.850Z",
      "source_type": "cov",
      "device_id": 864077,
      "device_name": "P864-864077",
      "controller_model": "P864",
      "device_address": "192.168.0.160:47808",
      "object_type": "binary-input",
      "object_instance": 1,
      "object_id": "binary-input:1",
      "short_object_id": "BI-1",
      "point_name": "WD3 (WATER LEAK)",
      "property_label": "Water detected",
      "dashboard_label": "WD3",
      "connection_bus": "IN 1 • Dry Contact (LED 1)",
      "value": 1,
      "value_text": "Water Detected",
      "is_triggered": true,
      "is_alarm": true,
      "quality": "alarm",
      "status_flags": {
        "in_alarm": false,
        "fault": false,
        "overridden": false,
        "out_of_service": false
      }
    }
  ]
}
```

### Endpoint B: `POST /api/v1/bacnet/devices`

Sent on controller discovery, metadata sync, communication failure (`online: false`), and recovery (`online: true`). Cache the latest controller health state in CDE so it can also be attached to outbound IMOPS payloads and forwarded to IMOPS's controller status endpoint.

```json
{
  "gateway_id": "zaarr-bacnet-gw-01",
  "site_name": "Smart Nation Exhibition System",
  "sent_at": "2026-11-13T01:20:00Z",
  "device": {
    "device_id": 864077,
    "object_name": "P864-864077",
    "model_name": "P864",
    "vendor_name": "Optergy",
    "vendor_id": 515,
    "firmware_revision": "2.4.0",
    "address": "192.168.0.160:47808",
    "online": true,
    "communication_status": "online",
    "point_count": 12,
    "discovered_at": "2026-11-13T00:00:05Z"
  }
}
```

---

## 2. Transformation Rules in CDE (Massage for IMOPS)

Transform each `TelemetryBatchEnvelope` into the clean IMOPS payload below:

1. **`sensor_id`:** Map from `short_object_id` (`AI-101`, `AI-102`, `AV-27126`, `AI-201`, `AI-202`, `BI-1`..`BI-7`). Maintain a configurable lookup map in CDE in case IMOPS later maps `short_object_id` to internal IMOPS asset UUIDs.
2. **`category`:**
   - `"environmental"` when `object_type` starts with `"analog-"` (`AI-101`, `AI-102`, `AV-27126`, `AI-201`, `AI-202`)
   - `"safety_security"` when `object_type` starts with `"binary-"` (`BI-1`..`BI-7`)
3. **`severity`:**
   - `"fault"` if `status_flags.fault == true` or `status_flags.out_of_service == true` or `quality == "fault"`
   - `"alarm"` if `is_alarm == true`
   - `"event"` if `is_triggered == true` and `is_alarm == false` (e.g., `BI-2` Motion Detected)
   - `"normal"` otherwise
4. **Other fields:**
   - `group` ⬅ `dashboard_label`
   - `sensor_name` ⬅ `point_name`
   - `metric` ⬅ `property_label`
   - `value` ⬅ `value`
   - `unit` ⬅ `unit` (default `""`)
   - `display_text` ⬅ `value_text`
   - `update_type` ⬅ `source_type` (`"poll"` or `"cov"`)
   - `updated_at` ⬅ `timestamp`

### Outbound Payload Sent by CDE ➔ IMOPS (`POST /api/v1/sensors/bacnet/updates`)

```json
{
  "site_name": "Smart Nation Exhibition System",
  "gateway_id": "zaarr-bacnet-gw-01",
  "batch_id": "20261113T012000Z-42",
  "controller": {
    "device_id": 864077,
    "name": "P864-864077",
    "model": "P864",
    "ip_address": "192.168.0.160",
    "online": true,
    "communication_status": "online"
  },
  "sent_at": "2026-11-13T01:20:00Z",
  "sensors": [
    {
      "sensor_id": "AI-101",
      "group": "BW-INT-M",
      "sensor_name": "BW-INT-M (WIRELESS AIR TOUCH DISPLAY)",
      "metric": "Temperature",
      "category": "environmental",
      "value": 23.45,
      "unit": "°C",
      "display_text": "23.45 °C",
      "severity": "normal",
      "is_triggered": false,
      "is_alarm": false,
      "update_type": "poll",
      "updated_at": "2026-11-13T01:19:59.812Z"
    },
    {
      "sensor_id": "BI-1",
      "group": "WD3",
      "sensor_name": "WD3 (WATER LEAK)",
      "metric": "Water detected",
      "category": "safety_security",
      "value": 1,
      "unit": "",
      "display_text": "Water Detected",
      "severity": "alarm",
      "is_triggered": true,
      "is_alarm": true,
      "update_type": "cov",
      "updated_at": "2026-11-13T01:19:59.850Z"
    }
  ]
}
```

Also forward controller connectivity changes from `/api/v1/bacnet/devices` to IMOPS (`POST /api/v1/sensors/bacnet/controller-status`) when `device.online` changes.

---

## Deliverables Needed Back for Edge Gateway Setup

1. CDE API Gateway `base_url` (e.g. `https://cde-api.example.com`)
2. Confirmed paths (`/api/v1/bacnet/telemetry` and `/api/v1/bacnet/devices`)
3. `X-API-Key` secret for `zaarr-bacnet-gw-01`
