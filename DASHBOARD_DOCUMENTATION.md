# Akeyless CS Technical Dashboards — Internal Reference

**Audience:** Customer Success, CSE, internal stakeholders  
**Platform:** Grafana (`akeyless-analytics.com`)  
**Data source:** Active Customers Data (SQLite via `frser-sqlite-datasource`)

---

## Dashboard overview

| Dashboard | UID | Use when |
|-----------|-----|----------|
| **Akeyless CS — Account Technical Dashboard** | `akeyless-cs-account-adoption` | Deep dive on **one customer** (one or all of their account IDs) |
| **Akeyless CS — Multi-Account Technical Dashboard** | `akeyless-cs-multi-account` | Compare **multiple customers** side by side |

Both dashboards cover the same four products: **SM**, **CLM**, **SRA**, **PM**.

---

## Shared concepts

### Product mapping

| Label | Product code | Purchased limit (HubSpot) |
|-------|--------------|---------------------------|
| SM — Secrets Management | `sm` | `clients_sm` |
| CLM — Certificate Lifecycle Management | `ca` | `clients_ca` |
| SRA — Secure Remote Access | `sra` | `clients_sra` |
| PM — Password Management | `apm` | `clients_pm` |

### Data sources (reports)

| Report type | Used for |
|-------------|----------|
| `ObjectsReport` | SM / SRA / PM — Used, Exceeded, monthly utilization %, Adoption Status contract-year usage, most risk panels |
| `certificate_analysis` | **CLM** — certificate counts (`ca_self_signed − risk_expired`, max per day/month) |
| `report_clients` + `report_clients_product_info` | CLM fallback, Access Type Breakdown |
| `report_objects` | Objects Info, trend/anomaly panels, Best Practice auth/secret counts |

### Time Range filter

Applies to most panels (not Grafana’s top-right time picker).

| Option | Window |
|--------|--------|
| Last 3 / 6 / 12 Months | Rolling from today |
| From Contract Start | Earliest `current_contract_start_date` for selected company(ies) |
| From Contract Start Last 12 Months | 12 months from contract anniversary (current or prior year) |

Default: **Last 12 Months**.

**Exception:** **Adoption Status — Contract Age & Usage** always uses **contract year** logic (anniversary-based), not the Time Range filter.

### Purchased limit special values

| Value | Meaning |
|-------|---------|
| `0` | No purchased limit on record → **Usage % is blank** |
| `999` / `99999` | Unlimited / placeholder → **Usage % is blank** |

---

## Account Technical Dashboard

### Filters

| Variable | Behavior |
|----------|----------|
| **Company Name** | Single customer |
| **Account ID** | One account, or **All** to aggregate every account under that company |
| **Time Range** | See table above |

### Header row

| Panel | Source |
|-------|--------|
| SLA | `account_support_level` (Gold / Platinum) |
| Account IDs | All account IDs for the company |
| Company name | Display only |
| Contract Start / End Date | HubSpot contract dates |
| **Days Since Contract** | **% of contract term elapsed** (start → end), not a day count |
| Selling Channel / Partner | HubSpot `partner` |
| Owners | CSM, CSE, Sales Executive |

### Product sections (SM, CLM, SRA, PM)

Each product has the panels below.

| Panel | Description |
|-------|-------------|
| **Usage %** | Period utilization vs purchased limit |
| **Purchased** | Licensed client limit from HubSpot (× months in range for period total) |
| **Used** | Sum of monthly client usage (`amount + exceeded`) across Time Range via `ObjectsReport` |
| **Exceeded** | Sum of exceeded clients across Time Range (SM, SRA, PM only) |
| **Usage AVG** | Average of monthly utilization % over Time Range |
| **Monthly Utilization %** | Month-by-month % table (color-coded) |

**CLM** has no Exceeded panel. CLM **Used** falls back to certificate object counts when CA client data is missing.

### Technical Trends & Anomalies

| Panel | Description |
|-------|-------------|
| **Objects Trend — Growth & Reduction Alerts** | MoM object count changes + stale objects (no growth in 3 months) |
| **Top Object Growth (Month over Month)** | Top 5 object types by absolute MoM increase |
| **New Use Cases — Secrets & Authentication** | New or expanding secret/auth types with adoption signals |

### Best Practice — Secrets & Authentication

| Panel | Description |
|-------|-------------|
| **Secret Type Mix** | Bar gauge — static vs dynamic + rotated secrets |
| **Authentication Method Mix** | Pie chart of auth method object counts |
| **Static Credentials vs Secretless Authentication** | Bar gauge — API key vs secretless auth (UID, CSP IAM, JWT, K8s). Bars scale proportionally to counts. |
| **Secrets — Static vs Dynamic/Rotated** | Table with static % and recommendation |
| **Authentication — Recommended Methods** | Table with API key % and recommendation |

### Risk Mitigation — SM, SRA, PM

| Panel | Description |
|-------|-------------|
| **Last Full Month Status — Usage vs Purchased Limit** | Last completed calendar month vs purchased |
| **Month over Month Usage Change** | Previous vs last full month; columns use **Last Month Used** (includes exceeded) |
| **Repeated Exceeded Clients — Last Month Detail** | Clients with repeated exceed events |
| **Adoption Status — Contract Age & Usage** | Contract-year usage vs annual purchased limit |
| **Access Type Breakdown** | Client usage by auth method for last full month |

---

## Multi-Account Technical Dashboard

### Filters

| Variable | Behavior |
|----------|----------|
| **Company Name** | Multi-select; **All** = entire portfolio |
| **Account ID** | Hidden (defaults to All) |
| **Time Range** | Same options as single-account |

### Differences from single-account

| Single-account only | Multi-account only |
|--------------------|--------------------|
| Header row (SLA, contract, owners) | — |
| Per-product gauge stats | **Summary by Customer** table per product |
| Objects Info (stacked trend chart) | **Objects Info by Customer** (table) |
| Secret Type Mix / Auth pie / Static vs Secretless bar gauge | Best-practice **tables only** (grouped by customer) |

**Same on both dashboards:** Technical Trends panels (Objects Trend, Top Object Growth, New Use Cases) and Risk Mitigation section — multi-account adds **Customer** / **Account IDs** columns.

Each product section has:

1. **Summary by Customer** — rolled up per company  
2. **Monthly Utilization % by Customer** — 24-month heatmap + **Avg (Last 3M)**

Trend, Best Practice, and Risk sections group rows **by customer** when multiple companies are selected.

Multi-account Best Practice tables:

| Panel | Description |
|-------|-------------|
| **Secrets — Static vs Dynamic/Rotated** | Per-customer static secret mix |
| **Authentication — Recommended Methods** | Per-customer static credentials vs secretless counts and recommendation |

---

## Calculations

### Usage % (single-account gauges)

```
Usage % = (Used + Exceeded) / Purchased × 100
```

- **Used / Exceeded:** sum of monthly `ObjectsReport` usage within Time Range (one report per account per day, latest per month).
- **Purchased:** HubSpot monthly limit × months in Time Range. Multiple accounts → first non-unlimited account limit (`LIMIT 1`).
- **Unlimited purchased** → blank %.

### Summary by Customer (multi-account)

Reflects the **last completed calendar month** — same logic as the matching column in **Monthly Utilization % by Customer**.

| Product | Used source |
|---------|-------------|
| SM, SRA, PM | Latest `ObjectsReport` in that month; Used = amount + exceeded |
| CLM | `certificate_analysis` reports; Used = max daily certs in month (no exceeded) |

```
Usage %   = Used / Purchased × 100
Purchased = SUM(clients_*) across all accounts for the company
```

### Monthly Utilization %

```
Utilization % = (Used + Exceeded) / Purchased × 100   [per month]
```

- Latest `ObjectsReport` **per account per calendar month** within Time Range.
- **Single-account:** one purchased limit (first account).
- **Multi-account:** `Purchased = SUM` of limits across accounts; `Used + Exceeded = SUM` across accounts.
- Months with no report → empty cell.

### Avg (Last 3M) — multi-account heatmap

Average of utilization % for the **last 3 completed calendar months** (current month excluded).

### Usage AVG — single-account gauge

Average of the **Monthly Utilization %** column values over Time Range.

### CLM Used

Primary: `report_clients` where `product = 'ca'`.  
Fallback: count of certificate objects (`report_objects`, type like `%certificate%`).

### Adoption Status — Used (Contract Year)

```
Used (Contract Year) = SUM(monthly amount + exceeded) from contract year start through last full month
```

- Uses **`ObjectsReport`** dedup path (same source as SM **Used** stat, but summed over contract year months).
- **Purchased (Annual)** = monthly HubSpot limit × 12.
- **Days Since Contract** = % of contract term elapsed (start → end).
- **Not** controlled by the Time Range filter.

### Last Full Month Status

Compares **last completed calendar month** usage vs purchased for SM, SRA, PM.

---

## Color thresholds (quick reference)

| Panel type | Coloring |
|------------|----------|
| Usage % gauge (single) | Red &lt; 20% · Orange 20–60% · Green ≥ 60% |
| Monthly util / multi Summary Usage % | Red &lt; 30% · Blue 30–70% · Green ≥ 70% |
| Static secrets / API key % (inverse) | Green when low · Yellow → Orange → Red when high |
| **Trend Alert** (Objects Trend) | **New — Review** (0 → N) · **Growth — Good** (>10% up) · **Stable Growth** (>0 and ≤10% up) · **Stable** (no change) · **Stable Decline** (<0 and ≥−10% down) · **Reduction — Review** (>10% down) · **Stale — No Growth in 3 Months** (flat across all 3 months) |
| **Change % / Growth %** | Red when negative · **Orange 0–30%** · **Blue 31–70%** · **Green ≥ 71%** |
| **Adoption Signal** (New Use Cases) | New Use Case (blue) · New Type at Scale (green) · **Expanding Pilot (green)** · Emerging (gray) |
| Static vs Secretless bar gauge | Static Credentials (red) · Secretless (green) |

Colors are guidance only — always read the numeric value.

---

## FAQs

**Why is Usage % empty?**  
Purchased is 0, unlimited (`999`/`99999`), or missing HubSpot data.

**Why is Adoption Status Used (Contract Year) different from SM Used?**  
**SM Used** follows the **Time Range** filter. **Adoption Status** sums usage from **contract year start** through the last full month. They should align when Time Range covers the same months.

**Why was Adoption Status Used showing 0 while SM Used showed a value?**  
Fixed: Adoption Status now uses the same **`ObjectsReport`** path as the usage stat panels.

**Why is a customer in Summary but not in the monthly heatmap?**  
Monthly table hides companies with no calculable utilization (`HAVING COUNT(util_pct) > 0`). Typical when purchased = 0 (e.g. no SM license on record).

**Why do Summary Used and monthly Used differ?**  
Summary reflects the **last full month** only and should match that month’s column in the heatmap below.

**Account ID = All — what gets aggregated?**  
All accounts under the selected company. Purchased/Used/% reflect combined totals (single-account) or per-company rollups (multi-account).

**Does the Grafana time picker (top-right) affect panels?**  
No. Panels follow the **Time Range** dashboard variable only (except Adoption Status — see above).

**How fresh is the data?**  
Depends on customer reporting cadence. Risk panels use the **last completed calendar month**. Check latest `report_date` in underlying tables if numbers look stale.

**CLM numbers look different from SM — is that a bug?**  
No. CLM uses **`certificate_analysis`** reports and counts active certificates, not `ObjectsReport` client rows.

**Multi-select company filter — any gotcha?**  
Use exact company names from the variable list. Filtering uses SQL `IN (...)` — names must match HubSpot `companies.name` exactly.

**Where is the dashboard JSON maintained?**  
`cs_hub/data/outputs/grafana/`. Regenerate after changes:

```bash
python3 cs_hub/data/outputs/grafana/generate_dashboards.py
```

---

## Related dashboards

| Dashboard | Purpose |
|-----------|---------|
| Portfolio Anomalies | Portfolio-wide anomaly tables (under-adopted, usage drops, stale reporting) |
| Test copies (`(TEST)` in title) | Sandbox UIDs for validating changes before production import |

---

*Last updated: June 2026 — aligned with production `dashboard-single-account.json` and `dashboard-multi-account.json`.*
