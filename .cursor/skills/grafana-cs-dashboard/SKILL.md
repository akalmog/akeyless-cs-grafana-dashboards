---
name: grafana-cs-dashboard
description: >-
  Designs and builds Grafana dashboards for Akeyless Customer Success Engineers
  from the CS usage SQLite schema (companies, reports, report_clients,
  certificates, objects). Produces panel SQL, dashboard layout, variables,
  anomaly-detection panels, and importable Grafana JSON. Use when the user asks
  to create or extend Grafana dashboards for account activity, usage tracking,
  adoption metrics, exceeded limits, certificate health, or CS anomaly detection.
---

# Grafana CS Dashboard Agent

Helps Customer Success Engineers build Grafana dashboards that track account activity, product adoption, usage vs contract, and anomalies — so CSEs can drive Akeyless adoption and spot risk early.

## When to use

Use this skill when the user wants to:

- Create or extend a **Grafana dashboard** for CS / usage analytics
- Write **SQL panel queries** against the CS usage database
- Design **anomaly-detection** panels (drops, exceeds, cert risk, under-adoption)
- Produce **importable Grafana dashboard JSON**

Before writing queries, read [schema-reference.md](schema-reference.md). For ready-made SQL patterns, read [panel-queries.md](panel-queries.md). For layout and JSON structure, read [examples.md](examples.md).

## Assumptions

- **Database**: SQLite (date functions like `date('now', '-12 months')`)
- **Primary key**: `account_id` links all tables via `companies.account_id`
- **Time filter**: `reports.report_date` (TEXT, `YYYY-MM-DD`)
- **Report types**: `clients_report`, `certificate_analysis`, `objects_report`
- **Grafana datasource**: SQLite plugin (e.g. `frser-sqlite-datasource`) unless the user specifies otherwise

If the datasource differs (Postgres, MySQL), adapt date functions and parameter syntax; keep table/column names unchanged.

## Workflow

Copy this checklist and track progress:

```
Task Progress:
- [ ] Step 1: Clarify scope
- [ ] Step 2: Design dashboard layout
- [ ] Step 3: Write SQL for each panel
- [ ] Step 4: Define variables and thresholds
- [ ] Step 5: Build Grafana JSON
- [ ] Step 6: Document CSE interpretation
```

### Step 1: Clarify scope

Confirm with the user (or infer from context):

| Question | Options |
|----------|---------|
| Audience | Single account drill-down vs portfolio / all accounts |
| Focus | Usage trends, adoption, exceeds, certificates, objects, anomalies |
| Time window | Last 12 months (default), from contract start, custom |
| Output | SQL only, layout spec, full Grafana JSON, or all three |

Default to **single-account drill-down** with `$account_id` variable plus a **portfolio anomalies** row if scope is unclear.

### Step 2: Design dashboard layout

Use this default row structure; add/remove rows based on scope:

| Row | Purpose | Default panels |
|-----|---------|----------------|
| **Account Summary** | Contract vs usage snapshot | Stat: contracted SM/PM/SRA/CA; Stat: current usage; Gauge: utilization % |
| **Usage Trends** | Adoption over time | Time series: monthly SM/APM/SRA; Bar: usage by access_type |
| **Exceeded Limits** | License pressure | Table: exceeded clients; Stat: total exceeded amount |
| **Certificate Health** | Expiry risk | Pie: risk_level; Table: critical/expired certs |
| **Objects** | Platform footprint | Bar: object_type counts; Time series: object growth |
| **Anomalies** | CSE action items | Table: usage drops; Table: under-adopted accounts; Stat: new exceeds |

Panel types: **stat** for KPIs, **timeseries** for trends, **table** for drill-down, **piechart** for composition, **gauge** for utilization.

### Step 3: Write SQL

Rules:

1. Always filter `clients_report` data through `reports` with `report_type = 'clients_report'` unless querying certificates or objects.
2. Use `$account_id` Grafana variable in `WHERE account_id = '$account_id'` for single-account panels.
3. For portfolio panels, omit account filter or use `$account_id` with **Include All** option.
4. Prefer `report_month` for monthly trends; use `report_date` for daily granularity and time-range filters.
5. Join path for product usage: `reports` → `report_clients` → `report_clients_product_info`.
6. Reuse queries from [panel-queries.md](panel-queries.md); do not reinvent common patterns.

### Step 4: Variables and thresholds

**Required dashboard variables:**

```sql
-- account_id (query variable)
SELECT account_id AS __value, name AS __text
FROM companies
ORDER BY name
```

Optional: `product` (`sm`, `apm`, `sra`, `ca`, `dp`, `pm`), `access_type`, `risk_level`.

**CSE thresholds** (adjust in panel overrides or alert rules):

| Signal | Threshold | CSE action |
|--------|-----------|------------|
| Utilization (used / contracted) | < 50% after 90 days post contract start | Adoption review call |
| Month-over-month usage drop | > 20% | Check gateway/auth changes, churn signal |
| Exceeded clients | > 0 | Expansion conversation or limit review |
| Critical + expired certs | > 0 | Certificate remediation workshop |
| Single access_type > 90% of clients | Concentration | Recommend additional auth methods |

### Step 5: Build Grafana JSON

1. Start from the skeleton in [examples.md](examples.md).
2. Set `"schemaVersion": 39` (or match user's Grafana version if known).
3. Each panel needs: `datasource`, `targets[].rawSql`, `gridPos`, `fieldConfig`.
4. Use `"rawQuery": true` for SQLite datasource targets.
5. Name panels clearly for CSEs (e.g. "SM Usage vs Contract — Last 12 Months").
6. Output JSON in a fenced `json` block the user can save as `dashboard.json` and import via **Dashboards → New → Import**.

### Step 6: Document CSE interpretation

After delivering SQL/JSON, add a short **CSE Playbook** section:

- What each row tells the CSE
- Which panels indicate **expansion** vs **churn risk**
- Suggested follow-up questions for the customer call

## Anomaly detection priorities

When the user asks for anomalies, always include panels from the **Anomaly Queries** section in [panel-queries.md](panel-queries.md):

1. **Usage drop** — MoM decline > 20%
2. **Under-adoption** — usage < 50% of contracted clients (SM/PM/SRA)
3. **New exceeds** — clients with `exceeded_amount > 0` in latest report vs prior
4. **Certificate risk** — `critical` or `expired` certs in latest certificate report
5. **Stale reporting** — no report in last 35 days
6. **Auth concentration** — one `access_type` dominates (> 90%)

## Output format

Deliver in this order:

```markdown
## Dashboard: [Name]

### Scope
[Single account | Portfolio] — [focus areas]

### Variables
[SQL for each variable]

### Panels
#### [Row name] — [Panel title]
- **Type**: stat | timeseries | table | ...
- **Purpose**: one sentence for CSE
- **SQL**: ...
- **Alert threshold** (if any): ...

### Grafana JSON
[importable JSON or path if written to file]

### CSE Playbook
[interpretation and recommended actions]
```

## Additional resources

| File | Purpose |
|------|---------|
| [schema-reference.md](schema-reference.md) | Full table schema, joins, field reference |
| [panel-queries.md](panel-queries.md) | Reusable SQL for panels and anomalies |
| [examples.md](examples.md) | Dashboard layout examples and JSON skeleton |
