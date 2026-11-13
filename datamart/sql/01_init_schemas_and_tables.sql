-- =============================================================================
--  CDE Security Incident Data Mart — Schema & Table Initialization (Phase 1)
--  Zones:
--    1. raw           (Bronze: Unmodified JSONB batches & ETL watermarks)
--    2. silver        (Curated: Conformed Star Schema dimensions & facts)
--    3. mart_security (Gold: Pre-aggregated Business Data Marts)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS mart_security;

-- =============================================================================
-- ZONE 1: RAW (BRONZE)
-- =============================================================================
CREATE TABLE IF NOT EXISTS raw.imops_api_payloads (
    batch_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    endpoint       VARCHAR(120) NOT NULL,
    site_name      VARCHAR(100),
    pulled_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    record_count   INTEGER NOT NULL DEFAULT 0,
    s3_object_key  TEXT,
    raw_payload    JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_raw_imops_pulled_at ON raw.imops_api_payloads(pulled_at DESC);
CREATE INDEX IF NOT EXISTS idx_raw_imops_endpoint ON raw.imops_api_payloads(endpoint, site_name);

CREATE TABLE IF NOT EXISTS raw.etl_watermarks (
    source_name          VARCHAR(80) PRIMARY KEY,
    last_polled_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_status          VARCHAR(20) NOT NULL DEFAULT 'SUCCESS',
    records_processed    INTEGER NOT NULL DEFAULT 0,
    last_error           TEXT
);

-- =============================================================================
-- ZONE 2: CURATED (SILVER — STAR SCHEMA)
-- =============================================================================
CREATE TABLE IF NOT EXISTS silver.dim_location (
    location_key   VARCHAR(64) PRIMARY KEY,
    site_id        VARCHAR(64),
    site_name      VARCHAR(120) NOT NULL,
    building_id    VARCHAR(64),
    building_name  VARCHAR(120) DEFAULT 'Main Building',
    floor_id       VARCHAR(64),
    floor_name     VARCHAR(120) DEFAULT 'Unassigned',
    zone_id        VARCHAR(64),
    zone_name      VARCHAR(120) DEFAULT 'Unassigned',
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS silver.dim_device (
    device_key             VARCHAR(64) PRIMARY KEY,
    device_id              VARCHAR(64),
    device_name            VARCHAR(120) NOT NULL,
    device_type            VARCHAR(60) DEFAULT 'CCTV',
    location_key           VARCHAR(64) REFERENCES silver.dim_location(location_key),
    site_name              VARCHAR(120),
    current_health_status  VARCHAR(40) DEFAULT 'online',
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS silver.dim_incident_type (
    incident_type_key   VARCHAR(64) PRIMARY KEY,
    incident_type_code  VARCHAR(80) NOT NULL,
    category            VARCHAR(60) NOT NULL DEFAULT 'Security / VA',
    default_severity    VARCHAR(20) NOT NULL DEFAULT 'medium',
    sla_target_minutes  INTEGER NOT NULL DEFAULT 15,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS silver.fact_incidents_current (
    incident_number    VARCHAR(50) PRIMARY KEY,
    event_id           VARCHAR(64),
    location_key       VARCHAR(64) REFERENCES silver.dim_location(location_key),
    device_key         VARCHAR(64) REFERENCES silver.dim_device(device_key),
    site_name          VARCHAR(120) NOT NULL DEFAULT 'Unassigned',
    building_name      VARCHAR(120) DEFAULT 'Main Building',
    floor_name         VARCHAR(120) DEFAULT 'Unassigned',
    zone_name          VARCHAR(120) DEFAULT 'Unassigned',
    device_name        VARCHAR(120) DEFAULT 'Unknown Device',
    incident_type      VARCHAR(80) NOT NULL,
    title              TEXT,
    severity           VARCHAR(20) NOT NULL DEFAULT 'medium',
    status             VARCHAR(30) NOT NULL DEFAULT 'active',
    operator_name      VARCHAR(100) DEFAULT 'Unassigned',
    detected_at        TIMESTAMPTZ NOT NULL,
    acknowledged_at    TIMESTAMPTZ,
    resolved_at        TIMESTAMPTZ,
    mtta_seconds       INTEGER,
    mttr_seconds       INTEGER,
    is_sla_breached    BOOLEAN DEFAULT FALSE,
    source_system      VARCHAR(40) DEFAULT 'imops',
    first_ingested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fact_inc_detected_at ON silver.fact_incidents_current(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_fact_inc_site_status ON silver.fact_incidents_current(site_name, status, severity);

CREATE TABLE IF NOT EXISTS silver.fact_incident_state_history (
    history_id         BIGSERIAL PRIMARY KEY,
    incident_number    VARCHAR(50) NOT NULL,
    old_status         VARCHAR(30),
    new_status         VARCHAR(30) NOT NULL,
    severity           VARCHAR(20),
    operator_name      VARCHAR(100),
    changed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fact_hist_inc ON silver.fact_incident_state_history(incident_number, changed_at DESC);

-- =============================================================================
-- ZONE 3: PUBLISHED (GOLD — BUSINESS DATA MARTS)
-- =============================================================================
CREATE TABLE IF NOT EXISTS mart_security.dm_daily_site_kpis (
    incident_date        DATE NOT NULL,
    site_name            VARCHAR(120) NOT NULL,
    floor_name           VARCHAR(120) NOT NULL DEFAULT 'All',
    zone_name            VARCHAR(120) NOT NULL DEFAULT 'All',
    incident_type        VARCHAR(80) NOT NULL,
    severity             VARCHAR(20) NOT NULL,
    total_incidents      INTEGER NOT NULL DEFAULT 0,
    active_count         INTEGER NOT NULL DEFAULT 0,
    acknowledged_count   INTEGER NOT NULL DEFAULT 0,
    resolved_count       INTEGER NOT NULL DEFAULT 0,
    resolution_rate_pct  NUMERIC(5,2) DEFAULT 0,
    avg_mtta_minutes     NUMERIC(10,2),
    avg_mttr_minutes     NUMERIC(10,2),
    sla_breach_count     INTEGER NOT NULL DEFAULT 0,
    refreshed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (incident_date, site_name, floor_name, zone_name, incident_type, severity)
);

CREATE TABLE IF NOT EXISTS mart_security.dm_incident_hotspots (
    site_name            VARCHAR(120) NOT NULL,
    zone_name            VARCHAR(120) NOT NULL,
    device_name          VARCHAR(120) NOT NULL,
    incident_type        VARCHAR(80) NOT NULL,
    incident_count_7d    INTEGER NOT NULL DEFAULT 0,
    incident_count_30d   INTEGER NOT NULL DEFAULT 0,
    critical_alarm_count INTEGER NOT NULL DEFAULT 0,
    last_incident_at     TIMESTAMPTZ,
    refreshed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (site_name, zone_name, device_name, incident_type)
);

CREATE TABLE IF NOT EXISTS mart_security.dm_sla_compliance (
    incident_date        DATE NOT NULL,
    site_name            VARCHAR(120) NOT NULL,
    operator_name        VARCHAR(100) NOT NULL DEFAULT 'Unassigned',
    severity             VARCHAR(20) NOT NULL,
    incidents_handled    INTEGER NOT NULL DEFAULT 0,
    within_sla_count     INTEGER NOT NULL DEFAULT 0,
    breached_sla_count   INTEGER NOT NULL DEFAULT 0,
    sla_compliance_pct   NUMERIC(5,2) DEFAULT 100.0,
    fastest_ack_sec      INTEGER,
    slowest_ack_sec      INTEGER,
    refreshed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (incident_date, site_name, operator_name, severity)
);

CREATE TABLE IF NOT EXISTS mart_security.dm_device_reliability (
    incident_date              DATE NOT NULL,
    site_name                  VARCHAR(120) NOT NULL,
    device_name                VARCHAR(120) NOT NULL,
    device_type                VARCHAR(60) NOT NULL DEFAULT 'CCTV',
    offline_events_count       INTEGER NOT NULL DEFAULT 0,
    incidents_triggered_count  INTEGER NOT NULL DEFAULT 0,
    current_health_status      VARCHAR(40) DEFAULT 'online',
    refreshed_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (incident_date, site_name, device_name)
);

CREATE TABLE IF NOT EXISTS mart_security.api_consumers (
    consumer_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_name           VARCHAR(120) NOT NULL,
    requester_email    VARCHAR(150) NOT NULL,
    department         VARCHAR(100) DEFAULT 'External Consumer',
    allowed_marts      TEXT[] NOT NULL DEFAULT ARRAY['daily-kpis','hotspots','sla-compliance','device-reliability'],
    api_key            VARCHAR(80) UNIQUE NOT NULL,
    status             VARCHAR(20) NOT NULL DEFAULT 'active',
    kong_synced        BOOLEAN DEFAULT FALSE,
    requests_count     INTEGER NOT NULL DEFAULT 0,
    last_used_at       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =============================================================================
-- STORED FUNCTION: Refresh Silver -> Gold Business Data Marts
-- =============================================================================
CREATE OR REPLACE FUNCTION mart_security.refresh_security_datamarts()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- 1. Refresh dm_daily_site_kpis
    DELETE FROM mart_security.dm_daily_site_kpis;
    INSERT INTO mart_security.dm_daily_site_kpis (
        incident_date, site_name, floor_name, zone_name, incident_type, severity,
        total_incidents, active_count, acknowledged_count, resolved_count,
        resolution_rate_pct, avg_mtta_minutes, avg_mttr_minutes, sla_breach_count, refreshed_at
    )
    SELECT
        DATE(detected_at AT TIME ZONE 'UTC') AS incident_date,
        COALESCE(site_name, 'Unassigned') AS site_name,
        COALESCE(floor_name, 'Unassigned') AS floor_name,
        COALESCE(zone_name, 'Unassigned') AS zone_name,
        COALESCE(incident_type, 'Unknown') AS incident_type,
        COALESCE(severity, 'medium') AS severity,
        COUNT(*) AS total_incidents,
        COUNT(*) FILTER (WHERE status IN ('active', 'attend_now')) AS active_count,
        COUNT(*) FILTER (WHERE status = 'acknowledged') AS acknowledged_count,
        COUNT(*) FILTER (WHERE status = 'resolved') AS resolved_count,
        ROUND((COUNT(*) FILTER (WHERE status = 'resolved')::NUMERIC / NULLIF(COUNT(*), 0)) * 100, 2) AS resolution_rate_pct,
        ROUND(AVG(mtta_seconds) / 60.0, 2) AS avg_mtta_minutes,
        ROUND(AVG(mttr_seconds) / 60.0, 2) AS avg_mttr_minutes,
        COUNT(*) FILTER (WHERE is_sla_breached = TRUE) AS sla_breach_count,
        NOW()
    FROM silver.fact_incidents_current
    GROUP BY 1, 2, 3, 4, 5, 6;

    -- 2. Refresh dm_incident_hotspots
    DELETE FROM mart_security.dm_incident_hotspots;
    INSERT INTO mart_security.dm_incident_hotspots (
        site_name, zone_name, device_name, incident_type,
        incident_count_7d, incident_count_30d, critical_alarm_count, last_incident_at, refreshed_at
    )
    SELECT
        COALESCE(site_name, 'Unassigned'),
        COALESCE(zone_name, 'Unassigned'),
        COALESCE(device_name, 'Unknown Device'),
        COALESCE(incident_type, 'Unknown'),
        COUNT(*) FILTER (WHERE detected_at >= NOW() - INTERVAL '7 days'),
        COUNT(*) FILTER (WHERE detected_at >= NOW() - INTERVAL '30 days'),
        COUNT(*) FILTER (WHERE severity IN ('critical', 'high')),
        MAX(detected_at),
        NOW()
    FROM silver.fact_incidents_current
    GROUP BY 1, 2, 3, 4;

    -- 3. Refresh dm_sla_compliance
    DELETE FROM mart_security.dm_sla_compliance;
    INSERT INTO mart_security.dm_sla_compliance (
        incident_date, site_name, operator_name, severity,
        incidents_handled, within_sla_count, breached_sla_count,
        sla_compliance_pct, fastest_ack_sec, slowest_ack_sec, refreshed_at
    )
    SELECT
        DATE(detected_at AT TIME ZONE 'UTC'),
        COALESCE(site_name, 'Unassigned'),
        COALESCE(operator_name, 'Unassigned'),
        COALESCE(severity, 'medium'),
        COUNT(*),
        COUNT(*) FILTER (WHERE NOT COALESCE(is_sla_breached, FALSE)),
        COUNT(*) FILTER (WHERE COALESCE(is_sla_breached, FALSE)),
        ROUND((COUNT(*) FILTER (WHERE NOT COALESCE(is_sla_breached, FALSE))::NUMERIC / NULLIF(COUNT(*), 0)) * 100, 2),
        MIN(mtta_seconds),
        MAX(mtta_seconds),
        NOW()
    FROM silver.fact_incidents_current
    GROUP BY 1, 2, 3, 4;

    -- 4. Refresh dm_device_reliability
    DELETE FROM mart_security.dm_device_reliability;
    INSERT INTO mart_security.dm_device_reliability (
        incident_date, site_name, device_name, device_type,
        offline_events_count, incidents_triggered_count, current_health_status, refreshed_at
    )
    SELECT
        DATE(f.detected_at AT TIME ZONE 'UTC'),
        COALESCE(f.site_name, 'Unassigned'),
        COALESCE(f.device_name, 'Unknown Device'),
        COALESCE(d.device_type, 'CCTV'),
        COUNT(*) FILTER (WHERE f.incident_type ILIKE '%offline%' OR f.title ILIKE '%offline%'),
        COUNT(*),
        COALESCE(MAX(d.current_health_status), 'online'),
        NOW()
    FROM silver.fact_incidents_current f
    LEFT JOIN silver.dim_device d ON f.device_key = d.device_key
    GROUP BY 1, 2, 3, 4;
END;
$$;

-- =============================================================================
-- BACNET EDGE GATEWAY TABLES (Silver Curated & Gold Published Mart)
-- =============================================================================
CREATE TABLE IF NOT EXISTS silver.bacnet_controllers (
    device_id             INTEGER PRIMARY KEY,
    gateway_id            VARCHAR(80) NOT NULL DEFAULT 'zaarr-bacnet-gw-01',
    site_name             VARCHAR(150) NOT NULL DEFAULT 'Smart Nation Exhibition System',
    name                  VARCHAR(120) NOT NULL,
    model                 VARCHAR(60) DEFAULT 'P864',
    vendor_name           VARCHAR(80) DEFAULT 'Optergy',
    vendor_id             INTEGER DEFAULT 515,
    firmware_revision     VARCHAR(40) DEFAULT '2.4.0',
    ip_address            VARCHAR(60),
    address               VARCHAR(80),
    online                BOOLEAN NOT NULL DEFAULT TRUE,
    communication_status  VARCHAR(40) NOT NULL DEFAULT 'online',
    point_count           INTEGER DEFAULT 12,
    discovered_at         TIMESTAMPTZ,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS silver.bacnet_sensor_history (
    reading_id            BIGSERIAL PRIMARY KEY,
    batch_id              VARCHAR(100),
    gateway_id            VARCHAR(80) NOT NULL DEFAULT 'zaarr-bacnet-gw-01',
    site_name             VARCHAR(150) NOT NULL DEFAULT 'Smart Nation Exhibition System',
    device_id             INTEGER NOT NULL DEFAULT 864077,
    sensor_id             VARCHAR(40) NOT NULL,
    group_label           VARCHAR(80),
    sensor_name           VARCHAR(160),
    metric                VARCHAR(100),
    category              VARCHAR(40),
    value                 DOUBLE PRECISION,
    unit                  VARCHAR(30),
    display_text          VARCHAR(120),
    severity              VARCHAR(30),
    is_triggered          BOOLEAN DEFAULT FALSE,
    is_alarm              BOOLEAN DEFAULT FALSE,
    update_type           VARCHAR(20),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ingested_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_silver_bacnet_hist_sensor ON silver.bacnet_sensor_history(sensor_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS mart_security.dm_bacnet_sensors (
    sensor_id             VARCHAR(40) PRIMARY KEY,
    site_name             VARCHAR(150) NOT NULL DEFAULT 'Smart Nation Exhibition System',
    gateway_id            VARCHAR(80) NOT NULL DEFAULT 'zaarr-bacnet-gw-01',
    controller_device_id  INTEGER NOT NULL DEFAULT 864077,
    controller_name       VARCHAR(120) DEFAULT 'P864-864077',
    controller_online     BOOLEAN DEFAULT TRUE,
    group_label           VARCHAR(80),
    sensor_name           VARCHAR(160),
    metric                VARCHAR(100),
    category              VARCHAR(40),
    value                 DOUBLE PRECISION,
    unit                  VARCHAR(30),
    display_text          VARCHAR(120),
    severity              VARCHAR(30),
    is_triggered          BOOLEAN DEFAULT FALSE,
    is_alarm              BOOLEAN DEFAULT FALSE,
    update_type           VARCHAR(20),
    last_batch_id         VARCHAR(100),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    refreshed_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


