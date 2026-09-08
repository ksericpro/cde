# Kong Gateway OSS Setup (with Kong Manager UI)

This setup runs **Kong Gateway OSS 3.9** with **Kong Manager (OSS UI)** enabled, backed by a PostgreSQL 15 database using Docker Compose.

---

## Port Allocations

| Port | Service | Description | Notes |
| :--- | :--- | :--- | :--- |
| **`8088`** | Public Proxy (HTTP) | Gateway entrypoint for clients/APIs | Remapped from `8000` to avoid conflict with CompreFace (`compreface-ui`) |
| **`8443`** | Public Proxy (HTTPS) | Secure Gateway entrypoint (SSL/TLS) | Standard Kong SSL proxy port |
| **`8001`** | Admin API (HTTP) | REST API to configure Kong | Internal / administrative use |
| **`8002`** | Kong Manager UI | Web Dashboard | Access this in your browser to manage Kong |

> [!NOTE]
> **Why do I see `no Route matched with those values` at `http://localhost:8088`?**
> This is the **expected and correct behavior**. Port `8088` is the traffic gateway proxy. Until you define a **Service** and a **Route**, Kong does not know where to proxy incoming requests. 
> To configure and manage Kong visually, open **[http://localhost:8002](http://localhost:8002)**.

---

## Core Kong Concepts

| Kong Concept | Real-World Analogy | What it does | Example |
| :--- | :--- | :--- | :--- |
| **Service** | The destination / backend room | Defines the target upstream API | `https://api.open-meteo.com` |
| **Route** | The door / path to enter | The public URL path clients call | `/weather` |
| **Consumer** | **The guest / client entering the door** | Represents **WHO** is calling your API | `mobile-app`, `user-alice`, `partner-corp` |
| **Plugin** | The security guard / receptionist | Intercepts requests for auth, rate limits, transforms | `key-auth`, `rate-limiting`, `cors` |

---

## What are Consumers?

A **Consumer** in Kong represents an external client, developer, user, or application calling your APIs. 

Without Consumers, your API is completely anonymous. With Consumers, you can:

1. **Authentication (API Keys, JWT, OAuth2)**
   - Issue distinct credentials (e.g. API keys) to each consumer to identify who is making the request.
2. **Tiered Rate Limiting & Quotas**
   - Apply different speed limits per client:
     - Free Consumer: 10 requests / minute
     - Premium Consumer: 1,000 requests / minute
3. **Access Control (ACLs & Whitelisting)**
   - Authorize specific consumers to access private routes while denying others.
4. **Analytics & Tracking**
   - Monitor usage per customer or app for auditing, billing, or telemetry.

---

## Quick Start

### 1. Start the Stack

Run the following command from the `apigw` directory:

```bash
docker compose up -d
```

This starts:
1. **`kong-db`**: PostgreSQL 15 database.
2. **`kong-migrations`**: Runs one-time database bootstrap migrations and exits.
3. **`kong-gateway`**: Kong Gateway instance with Kong Manager enabled.

### 2. Verify Services

Check running containers:
```bash
docker compose ps
```

`kong-gateway` and `kong-db` should report status as `Up` (healthy), and `kong-migrations` should report `Exited (0)`.

Test the Admin API:
```bash
curl.exe -i http://localhost:8001/
```
You should receive an HTTP `200 OK` response with Kong configuration details.

---

## Accessing Kong Manager Dashboard

Open your browser and navigate to:
👉 **[http://localhost:8002](http://localhost:8002)**

The Kong Manager dashboard allows you to visually manage:
- **Gateway Services**: Upstream backends / target APIs.
- **Routes**: External paths and host rules that map client traffic to Services.
- **Consumers**: Client identities and their security credentials.
- **Plugins**: Authentication, rate-limiting, request transformers, logging, etc.

---

## Working Examples & Tutorials

### Example 1: Weather API (`wttr.in`)

#### A. Create Service & Route via Admin API:
```bash
# 1. Create the Service
curl.exe -i -X POST http://localhost:8001/services -d "name=weather-service" -d "url=https://wttr.in"

# 2. Create the Route
curl.exe -i -X POST http://localhost:8001/services/weather-service/routes -d "name=weather-route" -d "paths[]=/weather" -d "strip_path=true"
```

#### B. Test in Browser or Terminal:
- **Plain Text / ASCII weather:**
  ```bash
  curl.exe http://localhost:8088/weather/Singapore?format=3
  ```
- **Structured JSON format (`?format=j1`):**
  ```bash
  curl.exe "http://localhost:8088/weather/Singapore?format=j1"
  ```

---

### Example 2: OpenAPI REST Weather API (`Open-Meteo`)

[Open-Meteo](https://open-meteo.com) is a free OpenAPI 3.0-compliant weather service that requires no API key.

```bash
# 1. Create Service
curl.exe -i -X POST http://localhost:8001/services -d "name=open-meteo-service" -d "url=https://api.open-meteo.com"

# 2. Create Route
curl.exe -i -X POST http://localhost:8001/services/open-meteo-service/routes -d "name=open-meteo-route" -d "paths[]=/meteo" -d "strip_path=true"

# 3. Query via Kong Proxy
curl.exe "http://localhost:8088/meteo/v1/forecast?latitude=1.35&longitude=103.82&current_weather=true"
```

---

### Example 3: Protecting APIs with Consumers & API Keys (`key-auth`)

Here is how to restrict an API so only authenticated Consumers can access it:

#### 1. Enable the `key-auth` Plugin on a Route:
```bash
curl.exe -i -X POST http://localhost:8001/routes/weather-route/plugins -d "name=key-auth"
```
*(Now requests without an API key will return `HTTP 401 Unauthorized`)*

#### 2. Create a Consumer (e.g., `alice`):
```bash
curl.exe -i -X POST http://localhost:8001/consumers -d "username=alice"
```

#### 3. Issue an API Key to Alice:
```bash
curl.exe -i -X POST http://localhost:8001/consumers/alice/key-auth -d "key=alice-secret-key"
```

#### 4. Call the Route with Alice's Key:
```bash
# In the Header:
curl.exe http://localhost:8088/weather/Singapore?format=3 -H "apikey: alice-secret-key"

# Or as a Query Parameter:
curl.exe "http://localhost:8088/weather/Singapore?format=3&apikey=alice-secret-key"
```

---

## How to Configure Your Translation Flow in the UI

Once inside Kong Manager at `http://localhost:8002`:

1. **Create a Service:** 
   - Go to **Gateway Services** -> **New Service**. 
   - Enter your target destination API base URL (e.g., `https://api.targetservice.com`).
2. **Create a Route:** 
   - Under that Service, select **Routes** -> **New Route**. 
   - Set the path your client or Virtual Assistant will call (e.g., `/va-hook`) and limit methods (e.g., `GET`, `POST`).
3. **Configure Request Translation / Transformation:**
   - Under the Route or Service, navigate to **Plugins** -> **Add Plugin**.
   - Use **Request Transformer** to inject API keys, rewrite headers, or append query strings needed by the target API.
   - If you need path rewriting, adjust the route's path matching rules or use the `path` rewrite settings in the plugin.

---

## Stopping & Restarting

- **Stop containers:**
  ```bash
  docker compose down
  ```
- **Stop and wipe database data (clean reset):**
  ```bash
  docker compose down -v
  ```
- **View logs:**
  ```bash
  docker compose logs -f kong
  ```
