# Panel Queries — CS Grafana Dashboard

Reusable SQLite queries. Replace `$account_id` with Grafana variable syntax. Add time filters as noted.

## Account summary

**Contracted vs used — SM (latest report):**

```sql
SELECT
  c.clients_sm AS contracted,
  r.clients_sm_total_amount AS used,
  ROUND(100.0 * r.clients_sm_total_amount / NULLIF(c.clients_sm, 0), 1) AS utilization_pct
FROM companies c
JOIN reports r ON r.account_id = c.account_id
WHERE c.account_id = '$account_id'
  AND r.report_type = 'clients_report'
ORDER BY r.report_date DESC
LIMIT 1
```

**All products — contracted vs used (stat row):**

```sql
SELECT
  c.name,
  c.clients_sm,  r.clients_sm_total_amount,
  c.clients_pm,  SUM(CASE WHEN rcp.product IN ('apm','pm') THEN rcp.amount ELSE 0 END) AS pm_used,
  c.clients_sra, SUM(CASE WHEN rcp.product = 'sra' THEN rcp.amount ELSE 0 END) AS sra_used,
  c.clients_ca,  SUM(CASE WHEN rcp.product = 'ca'  THEN rcp.amount ELSE 0 END) AS ca_used
FROM companies c
JOIN reports r ON r.account_id = c.account_id AND r.report_type = 'clients_report'
JOIN report_clients rc ON rc.report_id = r.id
JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
WHERE c.account_id = '$account_id'
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'clients_report'
  )
GROUP BY c.account_id
```

## Usage trends

**Monthly SM usage (12 months):**

```sql
SELECT
  r.report_month AS time,
  SUM(rcp.amount) AS sm_used
FROM reports r
JOIN report_clients rc ON rc.report_id = r.id
JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
WHERE r.account_id = '$account_id'
  AND r.report_type = 'clients_report'
  AND rcp.product = 'sm'
  AND r.report_date >= date('now', '-12 months')
GROUP BY r.report_month
ORDER BY r.report_month
```

**Monthly usage by product (multi-series time series):**

```sql
SELECT
  r.report_month AS time,
  rcp.product,
  SUM(rcp.amount) AS used
FROM reports r
JOIN report_clients rc ON rc.report_id = r.id
JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
WHERE r.account_id = '$account_id'
  AND r.report_type = 'clients_report'
  AND r.report_date >= date('now', '-12 months')
  AND rcp.product IN ('sm', 'apm', 'sra')
GROUP BY r.report_month, rcp.product
ORDER BY r.report_month, rcp.product
```

**Usage from contract start:**

```sql
SELECT r.report_month AS time, SUM(rcp.amount) AS used
FROM reports r
JOIN report_clients rc ON rc.report_id = r.id
JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
WHERE r.account_id = '$account_id'
  AND r.report_type = 'clients_report'
  AND rcp.product = 'sm'
  AND r.report_date >= (
    SELECT current_contract_start_date FROM companies WHERE account_id = '$account_id'
  )
GROUP BY r.report_month
ORDER BY r.report_month
```

## Auth method adoption

**Clients by access_type (latest report):**

```sql
SELECT rc.access_type, SUM(rc.amount) AS clients
FROM reports r
JOIN report_clients rc ON rc.report_id = r.id
WHERE r.account_id = '$account_id'
  AND r.report_type = 'clients_report'
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'clients_report'
  )
GROUP BY rc.access_type
ORDER BY clients DESC
```

**Access type × product heatmap data:**

```sql
SELECT rc.access_type, rcp.product, SUM(rcp.amount) AS amount
FROM reports r
JOIN report_clients rc ON rc.report_id = r.id
JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
WHERE r.account_id = '$account_id'
  AND r.report_type = 'clients_report'
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'clients_report'
  )
GROUP BY rc.access_type, rcp.product
```

## Exceeded limits

**Total exceeded by product (latest report):**

```sql
SELECT rcp.product, SUM(rcp.exceeded_amount) AS exceeded
FROM reports r
JOIN report_clients rc ON rc.report_id = r.id
JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
WHERE r.account_id = '$account_id'
  AND r.report_type = 'clients_report'
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'clients_report'
  )
  AND rcp.exceeded_amount > 0
GROUP BY rcp.product
```

**Exceeded clients detail table:**

```sql
SELECT
  e.access_id,
  e.product,
  e.highest_daily,
  e.highest_daily_date
FROM report_exceeded_clients_full_info e
JOIN reports r ON r.id = e.report_id
WHERE e.account_id = '$account_id'
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'clients_report'
  )
ORDER BY e.highest_daily DESC
```

## Certificate health

**Risk level breakdown (latest certificate report):**

```sql
SELECT cl.risk_level, COUNT(*) AS cert_count
FROM report_certificate_lines cl
JOIN reports r ON r.id = cl.report_id
WHERE cl.account_id = '$account_id'
  AND r.report_type = 'certificate_analysis'
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'certificate_analysis'
  )
GROUP BY cl.risk_level
```

**Critical and expired certificates:**

```sql
SELECT cl.common_name, cl.not_after, cl.risk_level
FROM report_certificate_lines cl
JOIN reports r ON r.id = cl.report_id
WHERE cl.account_id = '$account_id'
  AND r.report_type = 'certificate_analysis'
  AND cl.risk_level IN ('critical', 'expired')
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'certificate_analysis'
  )
ORDER BY cl.not_after ASC
```

## Objects

**Object counts by type (latest objects report):**

```sql
SELECT ro.object_type, ro.amount
FROM report_objects ro
JOIN reports r ON r.id = ro.report_id
WHERE ro.account_id = '$account_id'
  AND r.report_type = 'objects_report'
  AND r.report_date = (
    SELECT MAX(report_date) FROM reports
    WHERE account_id = '$account_id' AND report_type = 'objects_report'
  )
ORDER BY ro.amount DESC
```

**Object growth over time (total per report date):**

```sql
SELECT r.report_date AS time, SUM(ro.amount) AS total_objects
FROM reports r
JOIN report_objects ro ON ro.report_id = r.id
WHERE ro.account_id = '$account_id'
  AND r.report_type = 'objects_report'
  AND r.report_date >= date('now', '-12 months')
GROUP BY r.report_date
ORDER BY r.report_date
```

## Anomaly queries (portfolio)

**Accounts with > 20% MoM SM usage drop:**

```sql
WITH monthly AS (
  SELECT
    r.account_id,
    r.report_month,
    SUM(rcp.amount) AS sm_used,
    LAG(SUM(rcp.amount)) OVER (
      PARTITION BY r.account_id ORDER BY r.report_month
    ) AS prev_sm_used
  FROM reports r
  JOIN report_clients rc ON rc.report_id = r.id
  JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
  WHERE r.report_type = 'clients_report'
    AND rcp.product = 'sm'
    AND r.report_date >= date('now', '-12 months')
  GROUP BY r.account_id, r.report_month
),
latest AS (
  SELECT account_id, MAX(report_month) AS max_month FROM monthly GROUP BY account_id
)
SELECT c.name, m.account_id, m.report_month, m.sm_used, m.prev_sm_used,
  ROUND(100.0 * (m.sm_used - m.prev_sm_used) / NULLIF(m.prev_sm_used, 0), 1) AS pct_change
FROM monthly m
JOIN latest l ON l.account_id = m.account_id AND l.max_month = m.report_month
JOIN companies c ON c.account_id = m.account_id
WHERE m.prev_sm_used > 0
  AND m.sm_used < m.prev_sm_used * 0.8
ORDER BY pct_change ASC
```

**Under-adopted accounts (SM utilization < 50%):**

```sql
SELECT
  c.name,
  c.account_id,
  c.clients_sm AS contracted,
  r.clients_sm_total_amount AS used,
  ROUND(100.0 * r.clients_sm_total_amount / NULLIF(c.clients_sm, 0), 1) AS utilization_pct
FROM companies c
JOIN reports r ON r.account_id = c.account_id AND r.report_type = 'clients_report'
WHERE r.report_date = (
  SELECT MAX(r2.report_date) FROM reports r2
  WHERE r2.account_id = c.account_id AND r2.report_type = 'clients_report'
)
  AND c.clients_sm > 0
  AND r.clients_sm_total_amount < c.clients_sm * 0.5
ORDER BY utilization_pct ASC
```

**Accounts with new exceeds (latest vs prior report):**

```sql
WITH ranked AS (
  SELECT
    account_id,
    report_date,
    clients_sm_total_exceeded_amount,
    ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY report_date DESC) AS rn
  FROM reports
  WHERE report_type = 'clients_report'
)
SELECT
  c.name,
  curr.account_id,
  prev.clients_sm_total_exceeded_amount AS prev_exceeded,
  curr.clients_sm_total_exceeded_amount AS curr_exceeded
FROM ranked curr
JOIN ranked prev ON prev.account_id = curr.account_id AND prev.rn = 2
JOIN companies c ON c.account_id = curr.account_id
WHERE curr.rn = 1
  AND curr.clients_sm_total_exceeded_amount > prev.clients_sm_total_exceeded_amount
```

**Stale reporting (no report in 35+ days):**

```sql
SELECT
  c.name,
  c.account_id,
  MAX(r.report_date) AS last_report_date,
  CAST(julianday('now') - julianday(MAX(r.report_date)) AS INTEGER) AS days_since_report
FROM companies c
LEFT JOIN reports r ON r.account_id = c.account_id AND r.report_type = 'clients_report'
GROUP BY c.account_id
HAVING days_since_report > 35 OR last_report_date IS NULL
ORDER BY days_since_report DESC
```

**Auth method concentration (> 90% single access_type):**

```sql
WITH latest AS (
  SELECT account_id, MAX(report_date) AS max_date
  FROM reports WHERE report_type = 'clients_report'
  GROUP BY account_id
),
by_access AS (
  SELECT
    rc.account_id,
    rc.access_type,
    SUM(rc.amount) AS clients,
    SUM(SUM(rc.amount)) OVER (PARTITION BY rc.account_id) AS total_clients
  FROM report_clients rc
  JOIN reports r ON r.id = rc.report_id
  JOIN latest l ON l.account_id = r.account_id AND l.max_date = r.report_date
  GROUP BY rc.account_id, rc.access_type
)
SELECT c.name, b.account_id, b.access_type, b.clients,
  ROUND(100.0 * b.clients / b.total_clients, 1) AS pct
FROM by_access b
JOIN companies c ON c.account_id = b.account_id
WHERE b.total_clients > 0
  AND b.clients > b.total_clients * 0.9
ORDER BY pct DESC
```

**Certificate risk spike (accounts with critical/expired certs):**

```sql
SELECT c.name, cl.account_id, cl.risk_level, COUNT(*) AS cert_count
FROM report_certificate_lines cl
JOIN reports r ON r.id = cl.report_id
JOIN companies c ON c.account_id = cl.account_id
WHERE r.report_type = 'certificate_analysis'
  AND cl.risk_level IN ('critical', 'expired')
  AND r.report_date = (
    SELECT MAX(r2.report_date) FROM reports r2
    WHERE r2.account_id = cl.account_id AND r2.report_type = 'certificate_analysis'
  )
GROUP BY cl.account_id, cl.risk_level
ORDER BY cert_count DESC
```
