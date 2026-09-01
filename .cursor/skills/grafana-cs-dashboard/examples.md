# Dashboard Examples

## Example 1: Single-account CSE dashboard

**Name:** `Akeyless CS — Account Deep Dive`

**Variables:** `account_id` (required), built-in time range

**Rows:**

1. **Account Summary** — 4 stat panels (SM/PM/SRA/CA utilization %), 1 text panel with company name + contract start
2. **Usage Trends** — Time series (monthly by product), bar chart (access_type)
3. **Exceeded Limits** — Stat (total exceeded), table (exceeded client details)
4. **Certificate Health** — Pie (risk_level), table (critical/expired)
5. **Objects** — Bar (object_type), time series (total objects over time)
6. **Anomalies** — Stat panels flagging: MoM drop > 20%, utilization < 50%, any exceeds

## Example 2: Portfolio anomaly dashboard

**Name:** `Akeyless CS — Portfolio Anomalies`

**Variables:** optional `account_id` filter (Include All)

**Rows:**

1. **At-a-glance** — Stat: count of under-adopted, usage drops, new exceeds, stale reports
2. **Under-adoption** — Table from under-adopted query
3. **Usage drops** — Table from MoM drop query
4. **License pressure** — Table from new exceeds query
5. **Certificate risk** — Table from cert risk query
6. **Reporting health** — Table from stale reporting query

## Grafana JSON skeleton

Use as starting point; fill `targets`, `gridPos`, and panel IDs.

```json
{
  "annotations": { "list": [] },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [],
  "refresh": "1h",
  "schemaVersion": 39,
  "tags": ["akeyless", "customer-success", "usage"],
  "templating": {
    "list": [
      {
        "name": "account_id",
        "type": "query",
        "datasource": { "type": "frser-sqlite-datasource", "uid": "${DS_SQLITE}" },
        "query": "SELECT account_id AS __value, name AS __text FROM companies ORDER BY name",
        "refresh": 1,
        "includeAll": false,
        "multi": false,
        "label": "Account"
      }
    ]
  },
  "time": { "from": "now-12M", "to": "now" },
  "timepicker": {},
  "timezone": "browser",
  "title": "Akeyless CS — Account Deep Dive",
  "uid": "akeyless-cs-account",
  "version": 1
}
```

## Panel target template (SQLite)

```json
{
  "datasource": { "type": "frser-sqlite-datasource", "uid": "${DS_SQLITE}" },
  "rawQuery": true,
  "rawSql": "SELECT ... WHERE account_id = '$account_id'",
  "format": "table"
}
```

Format values: `table` for tables/stats, `time_series` for trend charts (requires `time` column).

## Example panel: SM utilization stat

```json
{
  "type": "stat",
  "title": "SM Utilization %",
  "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
  "targets": [
    {
      "datasource": { "type": "frser-sqlite-datasource", "uid": "${DS_SQLITE}" },
      "rawQuery": true,
      "rawSql": "SELECT ROUND(100.0 * r.clients_sm_total_amount / NULLIF(c.clients_sm, 0), 1) AS value FROM companies c JOIN reports r ON r.account_id = c.account_id WHERE c.account_id = '$account_id' AND r.report_type = 'clients_report' ORDER BY r.report_date DESC LIMIT 1",
      "format": "table"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "thresholds": {
        "mode": "absolute",
        "steps": [
          { "color": "red", "value": null },
          { "color": "yellow", "value": 50 },
          { "color": "green", "value": 80 }
        ]
      }
    }
  }
}
```

## CSE playbook snippets

**High utilization + exceeds:** Expansion opportunity — discuss additional client licenses or tier upgrade.

**Low utilization post-onboarding:** Schedule adoption review; check auth method setup, gateway deployment, and use-case mapping.

**Usage drop:** Investigate recent infra changes, auth method rotation, or competing tooling; cross-reference Pylon tickets and meeting notes.

**Certificate risk:** Offer certificate lifecycle workshop; link to Akeyless cert management use-cases.

**Auth concentration:** Recommend diversifying auth (e.g. move from api_key-only to SAML2/IAM for enterprise adoption).

**Stale reporting:** Verify bucket/report pipeline; account may have churned or data sync issue.
