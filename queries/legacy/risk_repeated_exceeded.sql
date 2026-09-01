-- Exceeded clients: latest month list + flag if same access ID also exceeded previous month.
WITH CompanyAccounts AS (
    SELECT DISTINCT account_id
    FROM companies
    WHERE account_id IS NOT NULL AND account_id != ''
      AND (
        '${company_name:raw}' IN ('All', '%', '$__all')
        OR name IN (${company_name:sqlstring})
        OR name = '${company_name}'
      )
      AND (
        '${account_id:raw}' IN ('All', '%', '$__all')
        OR LOWER('${account_id:raw}') = 'all'
        OR account_id = '${account_id}'
      )
),
MonthlyExceeded AS (
    SELECT
        e.account_id,
        strftime('%Y-%m', r.report_date) AS report_month,
        e.product,
        e.access_id,
        MAX(e.highest_daily) AS peak_daily,
        MAX(r.report_date) AS peak_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_exceeded_clients_full_info e ON e.account_id = ca.account_id
    INNER JOIN reports r ON r.id = e.report_id
    WHERE e.product IN ('sm', 'sra', 'apm')
      AND r.report_date >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY e.account_id, strftime('%Y-%m', r.report_date), e.product, e.access_id
),
LatestMonth AS (
    SELECT MAX(report_month) AS report_month FROM MonthlyExceeded
),
PreviousMonth AS (
    SELECT strftime('%Y-%m', date((SELECT report_month FROM LatestMonth) || '-01', '-1 month')) AS report_month
),
LatestExceeded AS (
    SELECT me.*
    FROM MonthlyExceeded me
    INNER JOIN LatestMonth lm ON lm.report_month = me.report_month
),
PreviousExceeded AS (
    SELECT me.account_id, me.product, me.access_id
    FROM MonthlyExceeded me
    INNER JOIN PreviousMonth pm ON pm.report_month = me.report_month
),
ExceededRows AS (
    SELECT
        le.account_id,
        CASE le.product
            WHEN 'sm' THEN 'SM — Secrets Management'
            WHEN 'sra' THEN 'SRA — Secure Remote Access'
            WHEN 'apm' THEN 'PM — Password Management'
        END AS product_label,
        le.access_id,
        le.report_month AS latest_month,
        le.peak_daily,
        le.peak_report_date,
        CASE
            WHEN pe.access_id IS NOT NULL THEN 'Yes — Also Exceeded Previous Month'
            ELSE 'Latest Month Only'
        END AS consecutive_exceeded,
        CASE
            WHEN pe.access_id IS NOT NULL THEN 'Repeated Exceeded — Review'
            ELSE 'Exceeded — Monitor'
        END AS risk,
        CASE WHEN pe.access_id IS NOT NULL THEN 0 ELSE 1 END AS sort_rank
    FROM LatestExceeded le
    LEFT JOIN PreviousExceeded pe
        ON pe.account_id = le.account_id
        AND pe.product = le.product
        AND pe.access_id = le.access_id
),
combined AS (
    SELECT
        account_id,
        product_label,
        access_id,
        latest_month,
        peak_daily,
        peak_report_date,
        consecutive_exceeded,
        risk,
        sort_rank
    FROM ExceededRows

    UNION ALL

    SELECT
        NULL AS account_id,
        'All Products' AS product_label,
        'No exceeded clients in latest month' AS access_id,
        COALESCE((SELECT report_month FROM LatestMonth), 'N/A') AS latest_month,
        NULL AS peak_daily,
        NULL AS peak_report_date,
        'N/A' AS consecutive_exceeded,
        'No Exceeded Clients — Healthy' AS risk,
        2 AS sort_rank
    WHERE NOT EXISTS (SELECT 1 FROM ExceededRows)
)
SELECT
    COALESCE(c.name, 'All Products') AS "Customer",
    COALESCE(c.account_id, '—') AS "Account ID",
    product_label AS "Product",
    access_id AS "Access ID",
    latest_month AS "Latest Month",
    peak_daily AS "Latest Peak Daily",
    peak_report_date AS "Latest Peak Date",
    consecutive_exceeded AS "Consecutive Exceeded",
    risk AS "Risk"
FROM combined
LEFT JOIN companies c ON c.account_id = combined.account_id
ORDER BY sort_rank, c.name, product_label, peak_daily DESC
