# =============================================================================
#  verify_datamart.ps1 — Verify CDE Security Data Mart Containers, Schemas,
#  Tables, MinIO Buckets, and Phase 2 Medallion ETL / Serving API
# =============================================================================
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  Verifying CDE Security Data Mart Stack (Phases 1 & 2)          " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

Write-Host "`n[1/4] Checking Running Containers..." -ForegroundColor Yellow
docker ps --filter "name=cde-datamart-db" --filter "name=cde-minio" --filter "name=cde-datamart-etl" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

Write-Host "`n[2/4] Checking PostgreSQL Medallion Schemas & Tables (raw, silver, mart_security)..." -ForegroundColor Yellow
docker exec cde-datamart-db psql -U cdeadmin -d cde_datamart -c "SELECT table_schema AS zone_schema, table_name FROM information_schema.tables WHERE table_schema IN ('raw', 'silver', 'mart_security') ORDER BY CASE table_schema WHEN 'raw' THEN 1 WHEN 'silver' THEN 2 ELSE 3 END, table_name;"

Write-Host "[3/4] Checking MinIO Lakehouse Buckets (/data)..." -ForegroundColor Yellow
docker exec cde-minio ls -1 /data | Where-Object { $_ -notmatch '^\.' } | ForEach-Object {
    Write-Host "  [OK] Bucket: s3://$_/" -ForegroundColor Green
}

Write-Host "`n[4/4] Checking Phase 2 Medallion ETL & Data Mart Serving API (http://localhost:8090)..." -ForegroundColor Yellow
try {
    $summary = Invoke-RestMethod -Uri "http://localhost:8090/api/v1/datamart/security/summary" -TimeoutSec 5
    $summary.zones | Format-List
} catch {
    Write-Host "  [WARN] Could not reach http://localhost:8090/api/v1/datamart/security/summary : $_" -ForegroundColor Red
}

Write-Host "=================================================================" -ForegroundColor Cyan
