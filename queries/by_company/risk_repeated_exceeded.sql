-- Exceeded clients summary for the last completed calendar month (by customer).
WITH CompanyAccounts AS (
    SELECT DISTINCT account_id, name AS company_name
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
    SELECT strftime('%Y-%m', date('now', 'start of month', '-1 month')) AS report_month
),
PreviousFullMonth AS (
    SELECT strftime('%Y-%m', date((SELECT report_month FROM LastFullMonth) || '-01', '-1 month')) AS report_month
),
MonthlyExceeded AS (
    SELECT
        ca.company_name,
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
    GROUP BY ca.company_name, e.account_id, strftime('%Y-%m', r.report_date), e.product, e.access_id
),
LatestExceeded AS (
    SELECT me.*
    FROM MonthlyExceeded me
    INNER JOIN LastFullMonth lfm ON lfm.report_month = me.report_month
),
PreviousExceeded AS (
    SELECT me.company_name, me.product, me.access_id
    FROM MonthlyExceeded me
    INNER JOIN PreviousFullMonth pfm ON pfm.report_month = me.report_month
),
CompanySummary AS (
    SELECT
        le.company_name,
        le.product,
        lfm.report_month AS latest_month,
        COUNT(DISTINCT le.access_id) AS exceeded_access_ids,
        MAX(le.peak_daily) AS max_peak_daily,
        MAX(le.peak_report_date) AS latest_peak_date,
        SUM(CASE WHEN pe.access_id IS NOT NULL THEN 1 ELSE 0 END) AS repeated_count
    FROM LatestExceeded le
    INNER JOIN LastFullMonth lfm ON 1 = 1
    LEFT JOIN PreviousExceeded pe
        ON pe.company_name = le.company_name
        AND pe.product = le.product
        AND pe.access_id = le.access_id
    GROUP BY le.company_name, le.product, lfm.report_month
),
combined AS (
    SELECT
        company_name,
        product,
        latest_month,
        exceeded_access_ids,
        max_peak_daily,
        latest_peak_date,
        repeated_count,
        CASE
            WHEN repeated_count > 0 THEN 'Yes — Repeated Exceeded Detected'
            ELSE 'Last Month Only'
        END AS consecutive_exceeded,
        CASE
            WHEN repeated_count > 0 THEN 'Repeated Exceeded — Review'
            ELSE 'Exceeded — Monitor'
        END AS risk,
        0 AS sort_rank
    FROM CompanySummary

    UNION ALL

    SELECT
        'All Products' AS company_name,
        NULL AS product,
        (SELECT report_month FROM LastFullMonth) AS latest_month,
        NULL AS exceeded_access_ids,
        NULL AS max_peak_daily,
        NULL AS latest_peak_date,
        NULL AS repeated_count,
        'N/A' AS consecutive_exceeded,
        'No Exceeded Clients — Healthy' AS risk,
        2 AS sort_rank
    WHERE NOT EXISTS (SELECT 1 FROM CompanySummary)
)
SELECT
    company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = combined.company_name) AS "Account IDs",
    CASE product
        WHEN 'sm' THEN 'SM'
        WHEN 'sra' THEN 'SRA'
        WHEN 'apm' THEN 'PWM'
        ELSE 'All Products'
    END AS "Product",
    latest_month AS "Month",
    exceeded_access_ids AS "Exceeded Access IDs",
    max_peak_daily AS "Max Peak Daily",
    latest_peak_date AS "Last Peak Date",
    repeated_count AS "Repeated Access IDs",
    consecutive_exceeded AS "Consecutive Exceeded",
    risk AS "Risk"
FROM combined
ORDER BY sort_rank, company_name, product
