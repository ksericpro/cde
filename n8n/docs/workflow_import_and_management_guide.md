# n8n Workflow Import & Lifecycle Management Guide

This guide documents the procedures, command-line alternatives, troubleshooting steps, and operational best practices for importing, publishing, and verifying workflows in the **n8n Workflow Engine** (`n8n-server`).

---

## 1. Quick Reference: CLI Workflow Import & Activation

When importing via CLI, execute the following commands from the root or `n8n/` directory:

```powershell
# Step 1: Copy workflow JSON into the n8n container
docker cp c:/Projects/cde/n8n/workflows/proscalar_ingestion_workflow.json n8n-server:/tmp/workflow.json

# Step 2: Import workflow into the n8n database
docker exec n8n-server n8n import:workflow --input=/tmp/workflow.json

# Step 3: Find the assigned Workflow ID (if updating existing workflow)
docker exec n8n-server n8n export:workflow --all --pretty

# Step 4: Publish/Activate the workflow (Current ID: L0fSnJ8zdJUbcqEf)
docker exec n8n-server n8n publish:workflow --id=L0fSnJ8zdJUbcqEf

# Step 5: Restart the container to load and activate webhooks
docker restart n8n-server
```

### Verification
Confirm the workflow is active in the container startup logs:
```powershell
docker logs --tail 25 n8n-server
```
Expected output:
```text
Start Active Workflows:
Activated workflow "Proscalar Webhook Ingestion Pipeline (Option C)" (ID: L0fSnJ8zdJUbcqEf)
Editor is now accessible via: https://localhost:5678
```

---

## 2. Web UI Import Methods & Common Pitfalls

### Method A: Direct Canvas Paste (Recommended for UI)
The fastest and most reliable way to load a workflow into the browser without dealing with file dialog freezes:
1. Open the workflow file in your editor: `c:\Projects\cde\n8n\workflows\proscalar_ingestion_workflow.json`.
2. Select all (`Ctrl + A`) and copy (`Ctrl + C`).
3. In the n8n canvas (e.g., `https://10.99.32.55:5678`), click on the empty canvas area.
4. Press **`Ctrl + V`**. All nodes and connectors will paste immediately onto the board.
5. Click **Save** in the top right.

### Method B: "Import from File" via UI
1. From the top bar, click the **`...`** (more options) next to the workflow title.
2. Click **Import from file**.
3. Select `proscalar_ingestion_workflow.json` (do **not** select Postman collections or fixture files).
4. Turn on the **Active** toggle (top right) and click **Save**.

---

## 3. Why UI "Import by File" Can Stall or Hang

| Common Cause | Root Cause | Solution |
| :--- | :--- | :--- |
| **Wrong File Format** | Trying to import a Postman Collection (e.g. `docs/imops_proscalar.json`) or test fixture (`alarm_12008.json`) instead of an n8n export JSON. | Ensure the file begins with `"nodes": [...]` and `"connections": {...}`. Postman collections are HTTP test scripts, not n8n workflow graphs. |
| **Working in a New Draft** | Navigating to `/workflow/<id>?new=true` creates a blank draft while the production workflow is already active under a separate ID. | Click **Overview** in the left sidebar to locate the existing workflow (`L0fSnJ8zdJUbcqEf`). |
| **Air-Gapped / Isolated Network Latency** | n8n frontend trying to resolve external fonts, node community catalogs, or telemetry endpoints behind an air-gapped corporate firewall. | Use the CLI import method (`docker exec n8n-server n8n import:workflow ...`) or canvas paste (`Ctrl + V`). |
| **Node.js Webhook Registration Lock** | Updating a workflow while active in single-container mode without restarting the process. | Run `docker restart n8n-server` to force the workflow engine to re-register routes. |

---

## 4. Current Production Workflow Reference

- **Workflow Name:** `Proscalar Webhook Ingestion Pipeline (Option C)`
- **Workflow ID:** `L0fSnJ8zdJUbcqEf`
- **Owner Project:** `qH7u1U4xcN862fg6` (`Eric See <ksericpro@gmail.com>`)
- **Direct Web UI URL:** `https://10.99.32.55:5678/workflow/L0fSnJ8zdJUbcqEf`
- **Source JSON File:** `c:\Projects\cde\n8n\workflows\proscalar_ingestion_workflow.json`
- **Backup File:** `c:\Projects\cde\n8n\workflows\proscalar_ingestion_workflow.backup.json`
- **Ingress Webhook Route:** `POST https://10.99.32.55:5678/webhook/proscalar`
- **Kong Reverse Proxy Target:** `http://localhost:8088/api/proscalar/webhook` $\rightarrow$ `n8n-server:5678/webhook/proscalar`
