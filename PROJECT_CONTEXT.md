# Project Context — Akeyless CS Grafana Dashboards

This repository is the dedicated workspace for building and maintaining Customer Success technical dashboards used on `akeyless-analytics.com`.

## What this repo contains

| Area | Location | Purpose |
|------|----------|---------|
| Dashboard generator | `generate_dashboards.py` | Builds importable Grafana JSON from SQL + panel config |
| SQL queries | `queries/` | Single-account queries; `queries/by_company/` for multi-account |
| Generated dashboards | `dashboard-*.json` | Import into Grafana after regeneration |
| User documentation | `DASHBOARD_DOCUMENTATION.md` | Confluence-style reference for CSEs |
| Cursor agent skill | `.cursor/skills/grafana-cs-dashboard/` | Schema, panel patterns, and workflow for AI-assisted development |

## Dashboards

| File | Grafana UID | Audience |
|------|-------------|----------|
| `dashboard-single-account.json` | `akeyless-cs-account-adoption` | Deep dive on one customer |
| `dashboard-multi-account.json` | `akeyless-cs-multi-account` | Compare multiple customers |
| `dashboard-portfolio-anomalies.json` | portfolio anomalies | Cross-account risk signals |

## Data source

- **Grafana datasource:** Active Customers Data (SQLite via `frser-sqlite-datasource`)
- **Plugin fields:** `queryText` / `rawQueryText` / `queryType` (not `rawSql`)
- **Default binding:** `uid: null` (org default datasource)

## Key design decisions

### Time windows

Different panels use different time logic — do not assume one global window:

| Logic | Used by |
|-------|---------|
| Dashboard **Time Range** variable | Most usage charts, Best Practice, Gateway panels |
| **Last 3 completed calendar months** | Objects Trend, Access Type — Used Clients (Last 3 Months) |
| **Last completed calendar month** | Access Type Breakdown snapshot |
| **Contract year** (anniversary) | Adoption Status — Contract Age & Usage |

### Products

| Label | DB code | Purchased column |
|-------|---------|------------------|
| SM | `sm` | `clients_sm` |
| CLM | `ca` | `clients_ca` |
| SRA | `sra` | `clients_sra` |
| PWM (was PM) | `apm` | `clients_pm` |

### Trend alert labels (Objects Trend)

| Label | Definition |
|-------|------------|
| Growth — Good | End count > start count × 1.1 |
| Stable Growth | End count > start count (≤ 10% growth) |
| Stable | No meaningful change |
| Stable Decline | End count < start count (≥ −10%) |
| Reduction — Review | End count < start count × 0.9 |
| New — Review | Start = 0, end > 0 |
| Stale — No Growth in 3 Months | Flat for 3 months with no other alert |

### Column conventions

- **Period** — `YYYY-MM → YYYY-MM` for trend panels
- **Count / Used / Total** — `X → Y` format for start/end values
- **Used** — in-limit clients (`amount`)
- **Exceeded** — over-limit clients (`exceeded_amount`)
- **Total** — Used + Exceeded (always `COALESCE(exceeded_amount, 0)`)

## Development workflow

```bash
# 1. Edit SQL in queries/ or panel config in generate_dashboards.py
# 2. Regenerate JSON
python3 generate_dashboards.py

# 3. Import updated JSON into Grafana (or paste JSON model)
```

## Recent change history (Sep 2026)

- PWM labeling (was PM) across dashboards
- Objects Trend: added Stable Growth / Stable Decline; re-added Change % column
- Access Type panels split: snapshot (Breakdown) vs 3-month trend (Used Clients)
- Fixed incomplete-month inclusion (panels now end on last completed calendar month)
- Removed empty Gateway column from multi-account Objects Info
- Removed Usage % / Change % from several risk panels per CSE feedback
- Multi-account CLM summary: fixed `used_in_limit` column naming

## Related resources

- Grafana instance: `akeyless-analytics.com`
- Schema reference: `.cursor/skills/grafana-cs-dashboard/schema-reference.md`
- Panel query patterns: `.cursor/skills/grafana-cs-dashboard/panel-queries.md`
