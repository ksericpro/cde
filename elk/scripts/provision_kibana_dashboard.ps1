# =============================================================================
#  provision_kibana_dashboard.ps1 — Provision Kibana Data View, Saved Searches,
#  Saved Lens Visualizations, and CDE / iMOPS Overview Dashboard
# =============================================================================
param(
    [string]$KibanaUrl = "http://localhost:5601"
)

$ErrorActionPreference = "Stop"
$headers = @{ "kbn-xsrf" = "true"; "Content-Type" = "application/json" }
$dataViewId = "6e6ed7f6-e9f5-4395-8492-6648b70603ad"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Provisioning Kibana Saved Searches, Lens Charts & Dashboard    " -ForegroundColor Cyan
Write-Host "  Kibana URL: $KibanaUrl                                         " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Update cde-live-raw-logs
$searchBody = @{
    attributes = @{
        title = "CDE Live Raw Logs"
        description = "Live stream of raw CDE, Kong Gateway, iMOPS, and n8n log documents"
        sort = @("@timestamp", "desc")
        columns = @(
            "log_source",
            "service.name",
            "request.uri",
            "response.status",
            "latencies.request",
            "container.name",
            "message"
        )
        kibanaSavedObjectMeta = @{
            searchSourceJSON = '{"highlightAll":true,"version":true,"query":{"query":"","language":"kuery"},"filter":[],"indexRefName":"kibanaSavedObjectMeta.searchSourceJSON.index"}'
        }
    }
    references = @(
        @{
            name = "kibanaSavedObjectMeta.searchSourceJSON.index"
            id = $dataViewId
            type = "index-pattern"
        }
    )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$KibanaUrl/api/saved_objects/search/cde-live-raw-logs?overwrite=true" -Method Post -Headers $headers -Body $searchBody | Out-Null
Write-Host "[+] Provisioned saved search: cde-live-raw-logs" -ForegroundColor Green

# 2. Create dedicated iMOPS saved search (imops-live-logs)
$imopsSearchBody = @{
    attributes = @{
        title = "iMOPS Application & API Logs (localhost:13000 + Kong Gateway)"
        description = "All iMOPS application container logs (imops-backend, imops-worker) and Kong Gateway iMOPS API calls"
        sort = @("@timestamp", "desc")
        columns = @(
            "log_source",
            "container.name",
            "service.name",
            "request.method",
            "request.uri",
            "response.status",
            "latencies.proxy",
            "message"
        )
        kibanaSavedObjectMeta = @{
            searchSourceJSON = '{"highlightAll":true,"version":true,"query":{"query":"log_source: \"imops-application\" or container.name: imops-* or service.name: *imops*","language":"kuery"},"filter":[],"indexRefName":"kibanaSavedObjectMeta.searchSourceJSON.index"}'
        }
    }
    references = @(
        @{
            name = "kibanaSavedObjectMeta.searchSourceJSON.index"
            id = $dataViewId
            type = "index-pattern"
        }
    )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$KibanaUrl/api/saved_objects/search/imops-live-logs?overwrite=true" -Method Post -Headers $headers -Body $imopsSearchBody | Out-Null
Write-Host "[+] Provisioned saved search: imops-live-logs" -ForegroundColor Green

# 3. Create Saved Lens Visualization 1: Log Volume Over Time by Source
$lens1Body = @'
{
  "attributes": {
    "title": "Log Volume Over Time by Source (iMOPS, Kong, n8n, System)",
    "visualizationType": "lnsXY",
    "state": {
      "visualization": {
        "legend": { "isVisible": true, "position": "right" },
        "valueLabels": "hide",
        "fittingFunction": "None",
        "axisTitlesVisibilitySettings": { "x": true, "yLeft": true, "yRight": true },
        "tickLabelsVisibilitySettings": { "x": true, "yLeft": true, "yRight": true },
        "labelsOrientation": { "x": 0, "yLeft": 0, "yRight": 0 },
        "gridlinesVisibilitySettings": { "x": true, "yLeft": true, "yRight": true },
        "preferredSeriesType": "bar_stacked",
        "layers": [
          {
            "layerId": "layer-vol-1",
            "accessors": ["col-count"],
            "position": "top",
            "seriesType": "bar_stacked",
            "showGridlines": false,
            "layerType": "data",
            "colorMapping": {
              "assignments": [],
              "specialAssignments": [{ "rule": { "type": "other" }, "color": { "type": "loop" }, "touched": false }],
              "paletteId": "eui_amsterdam_color_blind",
              "colorMode": { "type": "categorical" }
            },
            "xAccessor": "col-time",
            "splitAccessor": "col-source"
          }
        ]
      },
      "query": { "query": "", "language": "kuery" },
      "filters": [],
      "datasourceStates": {
        "formBased": {
          "layers": {
            "layer-vol-1": {
              "columns": {
                "col-time": {
                  "label": "@timestamp",
                  "dataType": "date",
                  "operationType": "date_histogram",
                  "sourceField": "@timestamp",
                  "isBucketed": true,
                  "scale": "interval",
                  "params": { "interval": "auto", "includeEmptyRows": true, "dropPartials": false }
                },
                "col-count": {
                  "label": "Count of records",
                  "dataType": "number",
                  "operationType": "count",
                  "isBucketed": false,
                  "scale": "ratio",
                  "sourceField": "___records___",
                  "params": { "emptyAsNull": true }
                },
                "col-source": {
                  "label": "Log Source",
                  "dataType": "string",
                  "operationType": "terms",
                  "scale": "ordinal",
                  "sourceField": "log_source.keyword",
                  "isBucketed": true,
                  "params": {
                    "size": 6,
                    "orderBy": { "type": "column", "columnId": "col-count" },
                    "orderDirection": "desc",
                    "otherBucket": true,
                    "missingBucket": false,
                    "parentFormat": { "id": "terms" },
                    "include": [],
                    "exclude": [],
                    "includeIsRegex": false,
                    "excludeIsRegex": false
                  }
                }
              },
              "columnOrder": ["col-source", "col-time", "col-count"],
              "incompleteColumns": {},
              "sampling": 1
            }
          }
        },
        "indexpattern": { "layers": {} },
        "textBased": { "layers": {} }
      },
      "internalReferences": [],
      "adHocDataViews": {}
    }
  },
  "references": [
    {
      "type": "index-pattern",
      "id": "6e6ed7f6-e9f5-4395-8492-6648b70603ad",
      "name": "indexpattern-datasource-layer-layer-vol-1"
    }
  ]
}
'@
Invoke-RestMethod -Uri "$KibanaUrl/api/saved_objects/lens/cde-lens-volume?overwrite=true" -Method Post -Headers $headers -Body $lens1Body | Out-Null
Write-Host "[+] Provisioned Lens chart: cde-lens-volume" -ForegroundColor Green

# 4. Create Saved Lens Visualization 2: iMOPS & Gateway Traffic by Service
$lens2Body = @'
{
  "attributes": {
    "title": "iMOPS & Gateway Traffic by Service",
    "visualizationType": "lnsPie",
    "state": {
      "visualization": {
        "shape": "donut",
        "layers": [
          {
            "layerId": "layer-svc-1",
            "primaryGroups": ["col-svc"],
            "metrics": ["col-cnt"],
            "numberDisplay": "percent",
            "categoryDisplay": "default",
            "legendDisplay": "default",
            "nestedLegend": false,
            "layerType": "data",
            "colorMapping": {
              "assignments": [],
              "specialAssignments": [{ "rule": { "type": "other" }, "color": { "type": "loop" }, "touched": false }],
              "paletteId": "eui_amsterdam_color_blind",
              "colorMode": { "type": "categorical" }
            }
          }
        ]
      },
      "query": { "query": "service.name: *", "language": "kuery" },
      "filters": [],
      "datasourceStates": {
        "formBased": {
          "layers": {
            "layer-svc-1": {
              "columns": {
                "col-svc": {
                  "label": "Service Name",
                  "dataType": "string",
                  "operationType": "terms",
                  "scale": "ordinal",
                  "sourceField": "service.name.keyword",
                  "isBucketed": true,
                  "params": {
                    "size": 8,
                    "orderBy": { "type": "column", "columnId": "col-cnt" },
                    "orderDirection": "desc",
                    "otherBucket": true,
                    "missingBucket": false,
                    "parentFormat": { "id": "terms" },
                    "include": [],
                    "exclude": [],
                    "includeIsRegex": false,
                    "excludeIsRegex": false
                  }
                },
                "col-cnt": {
                  "label": "Count of records",
                  "dataType": "number",
                  "operationType": "count",
                  "scale": "ratio",
                  "sourceField": "___records___",
                  "isBucketed": false,
                  "params": { "emptyAsNull": true }
                }
              },
              "columnOrder": ["col-svc", "col-cnt"],
              "sampling": 1,
              "ignoreGlobalFilters": false,
              "incompleteColumns": {}
            }
          }
        },
        "indexpattern": { "layers": {} },
        "textBased": { "layers": {} }
      },
      "internalReferences": [],
      "adHocDataViews": {}
    }
  },
  "references": [
    {
      "type": "index-pattern",
      "id": "6e6ed7f6-e9f5-4395-8492-6648b70603ad",
      "name": "indexpattern-datasource-layer-layer-svc-1"
    }
  ]
}
'@
Invoke-RestMethod -Uri "$KibanaUrl/api/saved_objects/lens/cde-lens-services?overwrite=true" -Method Post -Headers $headers -Body $lens2Body | Out-Null
Write-Host "[+] Provisioned Lens chart: cde-lens-services" -ForegroundColor Green

# 5. Create Saved Lens Visualization 3: iMOPS & n8n Status (Success vs Error)
$lens3Body = @'
{
  "attributes": {
    "title": "iMOPS & n8n Status (Success vs Error)",
    "visualizationType": "lnsPie",
    "state": {
      "visualization": {
        "shape": "donut",
        "layers": [
          {
            "layerId": "layer-status-1",
            "primaryGroups": ["col-outcome"],
            "metrics": ["col-cnt"],
            "numberDisplay": "values",
            "categoryDisplay": "default",
            "legendDisplay": "default",
            "nestedLegend": false,
            "layerType": "data",
            "colorMapping": {
              "assignments": [],
              "specialAssignments": [{ "rule": { "type": "other" }, "color": { "type": "loop" }, "touched": false }],
              "paletteId": "eui_amsterdam_color_blind",
              "colorMode": { "type": "categorical" }
            }
          }
        ]
      },
      "query": { "query": "service.name: *imops* or log_source: \"imops-application\" or log_source: \"n8n-workflow-engine\"", "language": "kuery" },
      "filters": [],
      "datasourceStates": {
        "formBased": {
          "layers": {
            "layer-status-1": {
              "columns": {
                "col-outcome": {
                  "label": "Outcome (Success vs Error)",
                  "dataType": "string",
                  "operationType": "filters",
                  "scale": "ordinal",
                  "isBucketed": true,
                  "params": {
                    "filters": [
                      {
                        "input": { "query": "response.status >= 200 and response.status < 400", "language": "kuery" },
                        "label": "200 OK (Success)"
                      },
                      {
                        "input": { "query": "response.status >= 400 or message: (*error* or *fail* or *exception*)", "language": "kuery" },
                        "label": "4xx / 5xx (Error)"
                      }
                    ]
                  }
                },
                "col-cnt": {
                  "label": "Count of events",
                  "dataType": "number",
                  "operationType": "count",
                  "scale": "ratio",
                  "sourceField": "___records___",
                  "isBucketed": false,
                  "params": { "emptyAsNull": true }
                }
              },
              "columnOrder": ["col-outcome", "col-cnt"],
              "sampling": 1,
              "ignoreGlobalFilters": false,
              "incompleteColumns": {}
            }
          }
        },
        "indexpattern": { "layers": {} },
        "textBased": { "layers": {} }
      },
      "internalReferences": [],
      "adHocDataViews": {}
    }
  },
  "references": [
    {
      "type": "index-pattern",
      "id": "6e6ed7f6-e9f5-4395-8492-6648b70603ad",
      "name": "indexpattern-datasource-layer-layer-status-1"
    }
  ]
}
'@
Invoke-RestMethod -Uri "$KibanaUrl/api/saved_objects/lens/cde-lens-status?overwrite=true" -Method Post -Headers $headers -Body $lens3Body | Out-Null
Write-Host "[+] Provisioned Lens chart: cde-lens-status" -ForegroundColor Green

# 6. Link all 3 saved Lens charts + 2 saved Search tables by panelRefName in cde-platform-overview
$panels = @(
    @{
        gridData = @{ x = 0; y = 0; w = 20; h = 14; i = "panel-vol" }
        panelIndex = "panel-vol"
        panelRefName = "panel_vol"
        type = "lens"
        embeddableConfig = @{ enhancements = @{} }
    },
    @{
        gridData = @{ x = 20; y = 0; w = 14; h = 14; i = "panel-svc" }
        panelIndex = "panel-svc"
        panelRefName = "panel_svc"
        type = "lens"
        embeddableConfig = @{ enhancements = @{} }
    },
    @{
        gridData = @{ x = 34; y = 0; w = 14; h = 14; i = "panel-status" }
        panelIndex = "panel-status"
        panelRefName = "panel_status"
        type = "lens"
        embeddableConfig = @{ enhancements = @{} }
    },
    @{
        gridData = @{ x = 0; y = 14; w = 48; h = 18; i = "imops-logs-stream" }
        panelIndex = "imops-logs-stream"
        panelRefName = "panel_imops_logs_stream"
        type = "search"
        embeddableConfig = @{ title = "iMOPS Application & API Log Stream (localhost:13000 + Kong Gateway)" }
    },
    @{
        gridData = @{ x = 0; y = 32; w = 48; h = 18; i = "raw-logs-stream" }
        panelIndex = "raw-logs-stream"
        panelRefName = "panel_raw_logs_stream"
        type = "search"
        embeddableConfig = @{ title = "All CDE Unified Live Raw Log Stream" }
    }
)

$dashBody = @{
    attributes = @{
        title = "CDE Platform Overview"
        description = "Unified Centralized Logging Dashboard for iMOPS, Kong Gateway, n8n, and CDE Platform Services"
        timeRestore = $true
        timeFrom = "now-24h"
        timeTo = "now"
        refreshInterval = @{ pause = $false; value = 10000 }
        optionsJSON = '{"useMargins":true,"syncColors":false,"syncCursor":true,"syncTooltips":false,"hidePanelTitles":false}'
        panelsJSON = ($panels | ConvertTo-Json -Depth 10 -Compress)
        kibanaSavedObjectMeta = @{
            searchSourceJSON = '{"query":{"query":"","language":"kuery"},"filter":[]}'
        }
    }
    references = @(
        @{
            name = "panel_vol"
            id = "cde-lens-volume"
            type = "lens"
        },
        @{
            name = "panel_svc"
            id = "cde-lens-services"
            type = "lens"
        },
        @{
            name = "panel_status"
            id = "cde-lens-status"
            type = "lens"
        },
        @{
            name = "panel_imops_logs_stream"
            id = "imops-live-logs"
            type = "search"
        },
        @{
            name = "panel_raw_logs_stream"
            id = "cde-live-raw-logs"
            type = "search"
        }
    )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri "$KibanaUrl/api/saved_objects/dashboard/cde-platform-overview?overwrite=true" -Method Post -Headers $headers -Body $dashBody | Out-Null
Write-Host "[+] Provisioned dashboard: cde-platform-overview" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
