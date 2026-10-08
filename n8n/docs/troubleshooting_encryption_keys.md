# n8n Troubleshooting: Encryption Keys & Multi-Host Deployment

This guide addresses common startup errors related to encryption keys, database state, and IP/hostname configuration in n8n deployments for CDE.

---

## 1. Issue: "Mismatching encryption keys"

### Error Message
```text
Error: Failed to load command "start"
Error: Mismatching encryption keys. The encryption key in the settings file /root/.n8n/config does not match the N8N_ENCRYPTION_KEY env var. Please make sure both keys match.
```

### Cause
When n8n initializes, it compares:
1. The **`N8N_ENCRYPTION_KEY`** passed in the environment (via `.env` or `docker-compose.yml`).
2. The **`encryptionKey`** value stored in `/root/.n8n/config` (mapped locally to `n8n/n8n_data/config`).

If these two values differ, n8n refuses to boot to prevent data corruption.

### Solutions

#### Solution A: Align `.env` with the existing `config` file (Preserve saved data)
1. Inspect the key currently saved in `n8n_data/config`:
   ```bash
   cat n8n_data/config
   ```
2. Set `N8N_ENCRYPTION_KEY` in `n8n/.env` to that exact value:
   ```env
   N8N_ENCRYPTION_KEY=cde-n8n-secret-encryption-key-2026-cde-pipeline
   ```
3. Recreate the container:
   ```bash
   docker compose down
   docker compose up -d
   ```

#### Solution B: Reset the `config` file (If you changed the key in `.env`)
If you want n8n to adopt your new `N8N_ENCRYPTION_KEY`:
```bash
# Linux
docker compose down
rm -f n8n_data/config
docker compose up -d

# Windows PowerShell
docker compose down
Remove-Item -Force .\n8n_data\config
docker compose up -d
```
*Note: Workflows will remain intact. Any previously saved credentials using an old key will need to be re-entered in the UI.*

---

## 2. Issue: "Deployment key 'signing.hmac' cannot be read"

### Error Message
```text
Error: Deployment key 'signing.hmac' cannot be read with this instance encryption key
    at DeploymentKeyRepository.findActiveSigningSecret (...)
    at InstanceSettings.initSecret (...)
```

### Cause
The persistent SQLite database (`n8n_data/database.sqlite`) was created using a previous encryption key. The internal `signing.hmac` token in the database was encrypted with that old key and cannot be decrypted with the current key.

### Solutions

#### Solution A: Clean Database Initialization (Recommended for Production / New Setup)
If this is a fresh setup or you have exported your workflows (e.g. `n8n/workflows/proscalar_ingestion_workflow.json`):

```bash
# Linux
docker compose down
rm -f n8n_data/database.sqlite*
rm -f n8n_data/config
docker compose up -d

# Windows PowerShell
docker compose down
Remove-Item -Force .\n8n_data\database.sqlite*
Remove-Item -Force .\n8n_data\config
docker compose up -d
```

After startup:
1. Open the web interface at `https://<HOST>:5678`.
2. Complete the owner setup.
3. Import workflows from `n8n/workflows/`.

#### Solution B: Revert to the Database's Original Key
If the database was initialized with the default template key (`vFqkNzD0vZweaUiNmL7lOT7cSKotsEdA`), update `n8n/.env`:
```env
N8N_ENCRYPTION_KEY=vFqkNzD0vZweaUiNmL7lOT7cSKotsEdA
```
Delete the mismatching `config` file and restart:
```bash
rm -f n8n_data/config
docker compose down
docker compose up -d
```

---

## 3. Configuring Host IP for Remote / Production Access

When hosting n8n on a remote server (e.g., `10.99.32.55`), `localhost` must be updated in `n8n/.env`:

```env
# Change from localhost to server IP or FQDN
N8N_HOST=10.99.32.55
N8N_PORT=5678
N8N_PROTOCOL=https

# Public webhook endpoint displayed in n8n canvas & returned to callers
N8N_WEBHOOK_URL=https://10.99.32.55:5678/
```

### Why this is required:
1. **Webhook Generation:** n8n generates webhook trigger endpoints using `N8N_WEBHOOK_URL`. If kept as `localhost`, external services (Kong, IoT gateways, devices) cannot call the generated webhook URL.
2. **Reverse Proxy:** `docker/nginx.n8n.conf` uses `server_name _;` so Nginx accepts requests to `https://10.99.32.55:5678` automatically.
3. **Browser SSL Warning:** Self-signed certificates will display a security warning. Click **Advanced $\rightarrow$ Proceed to 10.99.32.55 (unsafe)**.
