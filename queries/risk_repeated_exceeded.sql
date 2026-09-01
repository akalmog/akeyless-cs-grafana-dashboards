-- Exceeded clients in the last completed calendar month.
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
LastFullMonth AS (
    SELECT strftime('%Y-%m', 'now', 'start of month', '-1 month') AS report_month
),
PreviousFullMonth AS (
    SELECT strftime('%Y-%m', date((SELECT report_month FROM LastFullMonth) || '-01', '-1 month')) AS report_month
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
      AND r.report_date >= {period_date_cutoff}
    GROUP BY e.account_id, strftime('%Y-%m', r.report_date), e.product, e.access_id
),
LatestExceeded AS (
    SELECT me.*
    FROM MonthlyExceeded me
    INNER JOIN LastFullMonth lfm ON lfm.report_month = me.report_month
),
PreviousExceeded AS (
    SELECT me.account_id, me.product, me.access_id
    FROM MonthlyExceeded me
    INNER JOIN PreviousFullMonth pfm ON pfm.report_month = me.report_month
),
ExceededRows AS (
    SELECT
        le.account_id,
        CASE le.product
            WHEN 'sm' THEN 'SM'
            WHEN 'sra' THEN 'SRA'
            WHEN 'apm' THEN 'PWM'
        END AS product_label,
        le.access_id,
        le.report_month AS latest_month,
        le.peak_daily,
        le.peak_report_date,
        CASE
            WHEN pe.access_id IS NOT NULL THEN 'Yes — Also Exceeded Previous Month'
            ELSE 'Last Month Only'
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
        (SELECT report_month FROM LastFullMonth) AS latest_month,
        NULL AS peak_daily,
        NULL AS peak_report_date,
        'N/A' AS consecutive_exceeded,
        'No Exceeded Clients — Healthy' AS risk,
        2 AS sort_rank
    WHERE NOT EXISTS (SELECT 1 FROM ExceededRows)
)
SELECT
    combined.access_id AS "Access ID",
    COALESCE(c.account_id, '—') AS "Account ID",
    product_label AS "Product",
    latest_month AS "Month",
    peak_daily AS "Last Peak Daily",
    peak_report_date AS "Last Peak Date",
    consecutive_exceeded AS "Consecutive Exceeded",
    risk AS "Risk"
FROM combined
LEFT JOIN companies c ON c.account_id = combined.account_id
ORDER BY sort_rank, c.account_id, product_label, peak_daily DESC
