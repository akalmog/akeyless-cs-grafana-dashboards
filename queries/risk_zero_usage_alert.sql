-- Month-over-month usage status for SM / SRA / PM — always one row per product.
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
Products AS (
    SELECT 'sm' AS product
    UNION ALL SELECT 'sra'
    UNION ALL SELECT 'apm'
),
MonthlyLatestReport AS (
    SELECT
        ca.account_id,
        strftime('%Y-%m', rc.report_date) AS report_month,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rc.report_date >= {period_date_cutoff}
    GROUP BY ca.account_id, strftime('%Y-%m', rc.report_date), rcp.product
),
MonthlyProductUsage AS (
    SELECT
        mlr.account_id,
        mlr.report_month,
        mlr.product,
        SUM(rcp.amount) AS used_clients
    FROM MonthlyLatestReport mlr
    INNER JOIN report_clients rc
        ON rc.account_id = mlr.account_id
        AND rc.report_date = mlr.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = mlr.product
    GROUP BY mlr.account_id, mlr.report_month, mlr.product
),
CompletedMonths AS (
    SELECT * FROM MonthlyProductUsage
    WHERE report_month < strftime('%Y-%m', 'now')
),
Ranked AS (
    SELECT
        mpu.*,
        ROW_NUMBER() OVER (PARTITION BY mpu.account_id, mpu.product ORDER BY mpu.report_month DESC) AS rn
    FROM CompletedMonths mpu
),
Latest AS (
    SELECT account_id, product, report_month, used_clients
    FROM Ranked
    WHERE rn = 1
),
Previous AS (
    SELECT account_id, product, report_month, used_clients
    FROM Ranked
    WHERE rn = 2
)
SELECT
    c.account_id AS "Account ID",
    CASE p.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
    END AS "Product",
    COALESCE(prev.report_month, 'N/A') AS "Previous Month",
    COALESCE(prev.used_clients, 0) AS "Previous Month Used",
    COALESCE(curr.report_month, 'N/A') AS "Latest Month",
    COALESCE(curr.used_clients, 0) AS "Latest Month Used",
    COALESCE(curr.used_clients, 0) - COALESCE(prev.used_clients, 0) AS "Change",
    CASE
        WHEN curr.report_month IS NULL THEN 'No Client Reports in Range'
        WHEN prev.report_month IS NULL THEN 'First Month in Range'
        WHEN prev.used_clients > 0 AND curr.used_clients = 0 THEN 'Zero Usage Drop — Review Immediately'
        WHEN curr.used_clients < prev.used_clients * 0.8 THEN 'Drop Over 20% — Review'
        WHEN curr.used_clients > prev.used_clients * 1.2 THEN 'Spike Over 20% — Review'
        ELSE 'Stable'
    END AS "Alert"
FROM CompanyAccounts ca
CROSS JOIN Products p
INNER JOIN companies c ON c.account_id = ca.account_id
LEFT JOIN Latest curr ON curr.account_id = ca.account_id AND curr.product = p.product
LEFT JOIN Previous prev ON prev.account_id = ca.account_id AND prev.product = p.product
WHERE curr.report_month IS NOT NULL
  AND curr.report_month != 'N/A'
ORDER BY c.account_id, p.product
