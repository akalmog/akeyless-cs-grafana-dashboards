# Akeyless CS Grafana Dashboards

Import-ready Grafana dashboards and SQL for Akeyless Customer Success technical analytics.

**Platform:** [akeyless-analytics.com](https://akeyless-analytics.com)  
**Datasource:** Active Customers Data (SQLite, `frser-sqlite-datasource`)

## Quick start

```bash
# Regenerate dashboard JSON after query or layout changes
python3 generate_dashboards.py
```

Import the generated JSON files into Grafana:

| File | Use when |
|------|----------|
| `dashboard-single-account.json` | One customer deep-dive |
| `dashboard-multi-account.json` | Multiple customers side-by-side |
| `dashboard-portfolio-anomalies.json` | Portfolio-wide anomaly tables |

## Documentation

| Doc | Contents |
|-----|----------|
| [DASHBOARD_DOCUMENTATION.md](DASHBOARD_DOCUMENTATION.md) | Full panel reference for CSEs (Confluence source) |
| [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) | Architecture, time-window rules, change history |
| [.cursor/skills/grafana-cs-dashboard/](.cursor/skills/grafana-cs-dashboard/) | Schema, SQL patterns, Cursor agent skill |

## Repository structure

```
├── generate_dashboards.py      # Dashboard builder
├── queries/                    # SQL per panel (single-account)
│   ├── by_company/             # Multi-account variants
│   └── legacy/                 # Archived queries
├── dashboard-*.json              # Generated Grafana exports
├── DASHBOARD_DOCUMENTATION.md    # End-user guide
└── .cursor/skills/             # AI development context
```

## Grafana import notes

1. Set **Active Customers Data** as the default datasource, or map on import.
2. After regeneration, re-import JSON or replace the dashboard JSON model in Grafana.
3. The SQLite plugin expects `queryText` / `queryType` — wrong field names cause "No data" with the plugin default query.

## Dashboard variables

| Variable | Single-account | Multi-account |
|----------|----------------|---------------|
| Company Name | Single select | Multi-select + All |
| Account ID | Filtered by company | Multi-select + All |
| Time Range | 3/6/12 months, contract start | Same |

## Products

| Label | DB code |
|-------|---------|
| SM | `sm` |
| CLM | `ca` |
| SRA | `sra` |
| PWM | `apm` |

## Cursor workspace

Open this folder as a dedicated Cursor workspace to continue dashboard development. The included Cursor skill (`.cursor/skills/grafana-cs-dashboard/`) provides schema reference and panel patterns for AI-assisted edits.

## License

Internal Akeyless Customer Success tooling.
