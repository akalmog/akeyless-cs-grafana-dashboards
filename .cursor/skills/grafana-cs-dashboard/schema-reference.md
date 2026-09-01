# CS Usage Database — Schema Reference

SQLite database for Akeyless Customer Success usage analytics. All tables link on `account_id`.

## Tables

### companies

Company data from HubSpot (one row per `account_id`).

| Field | Purpose |
|-------|---------|
| `account_id` | UNIQUE primary identifier |
| `name` | Company name |
| `clients_sm` | Contracted SM client count |
| `clients_pm` | Contracted PM client count |
| `clients_ca` | Contracted CA client count |
| `clients_sra` | Contracted SRA client count |
| `current_contract_start_date` | Contract start (for "From Contract Start" queries) |

### reports

Main report records with aggregated metrics.

| Field | Purpose |
|-------|---------|
| `id` | Report PK |
| `account_id` | FK → `companies.account_id` |
| `report_date` | Date filter (`YYYY-MM-DD`, TEXT) |
| `report_month` | Month bucket for trends |
| `report_type` | `clients_report`, `certificate_analysis`, `objects_report` |
| `clients_sm_total_amount` | Aggregated SM usage |
| `clients_sm_total_exceeded_amount` | Aggregated SM exceeded |

### report_clients

Individual client records by access type.

| Field | Purpose |
|-------|---------|
| `id` | PK |
| `report_id` | FK → `reports.id` |
| `account_id` | FK → `companies.account_id` |
| `access_type` | `api_key`, `aws_iam`, `saml2`, `universal_identity` |
| `amount` | Client count |
| `exceeded_amount` | Exceeded count |

Links to `report_clients_product_info` for product breakdown.

### report_clients_product_info

Product-specific usage per client record.

| Field | Purpose |
|-------|---------|
| `id` | PK |
| `report_client_id` | FK → `report_clients.id` |
| `product` | `sm`, `apm`, `sra`, `ca`, `dp`, `pm` |
| `amount` | Usage amount |
| `exceeded_amount` | Exceeded amount |

Products: **sm** (Secrets Management), **apm** (Password Management), **sra** (Secure Remote Access).

### report_exceeded_clients_full_info

Detailed exceeded client information.

| Field | Purpose |
|-------|---------|
| `id` | PK |
| `report_id` | FK → `reports.id` |
| `account_id` | FK → `companies.account_id` |
| `access_id` | Client access identifier |
| `product` | Product with exceed |
| `highest_daily` | Peak daily usage |
| `highest_daily_date` | Date of peak |

### report_certificate_lines

Individual certificate details.

| Field | Purpose |
|-------|---------|
| `id` | PK |
| `report_id` | FK → `reports.id` |
| `account_id` | FK → `companies.account_id` |
| `common_name` | Certificate CN |
| `not_after` | Expiration date |
| `risk_level` | `healthy`, `warning`, `critical`, `expired` |

### report_objects

Object counts from ObjectsReport.

| Field | Purpose |
|-------|---------|
| `id` | PK |
| `report_id` | FK → `reports.id` |
| `account_id` | FK → `companies.account_id` |
| `object_type` | Object type name |
| `amount` | Count |

## Table connections

```
companies (account_id — UNIQUE)
    ↓
    ├─→ reports (account_id → companies.account_id)
    │       ↓
    │       ├─→ report_clients (report_id → reports.id)
    │       │       ↓
    │       │       └─→ report_clients_product_info (report_client_id → report_clients.id)
    │       │
    │       ├─→ report_exceeded_clients_full_info (report_id → reports.id)
    │       │
    │       ├─→ report_objects (report_id → reports.id)
    │       │
    │       └─→ report_certificate_lines (report_id → reports.id)
```

Flow: **Company → Reports → Client Records → Product Details**

## Key fields reference

| Field | Table | Purpose |
|-------|-------|---------|
| `account_id` | companies | Primary identifier — links all tables |
| `report_date` | reports | Date filter for time-based queries (`YYYY-MM-DD`) |
| `access_type` | report_clients | `api_key`, `aws_iam`, `saml2`, `universal_identity` |
| `product` | report_clients_product_info | `sm`, `apm`, `sra`, `ca`, `dp`, `pm` |
| `not_after` | report_certificate_lines | Certificate expiration date |
| `risk_level` | report_certificate_lines | `healthy`, `warning`, `critical`, `expired` |

## Common queries

**Latest report for an account:**

```sql
SELECT *
FROM reports
WHERE account_id = '$account_id'
ORDER BY report_date DESC
LIMIT 1
```

**Monthly SM usage:**

```sql
SELECT report_month, SUM(amount) AS used
FROM report_clients rc
JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
WHERE rcp.product = 'sm'
  AND rc.account_id = '$account_id'
GROUP BY report_month
```

**12-month time range filter:**

```sql
WHERE report_date >= date('now', '-12 months')
  AND report_date <= date('now')
```

**From contract start:**

```sql
WHERE report_date >= (
  SELECT current_contract_start_date
  FROM companies
  WHERE account_id = '$account_id'
)
```

## Important notes

- `account_id` is the primary key for linking tables
- `report_date` is TEXT in `YYYY-MM-DD` format
- Product names: `sm`, `apm`, `sra`, `ca`, `dp`, `pm`
- Access types: `api_key`, `aws_iam`, `saml2`, `universal_identity`
- Use `date('now', '-12 months')` for default time ranges
- `current_contract_start_date` used for "From Contract Start" queries
