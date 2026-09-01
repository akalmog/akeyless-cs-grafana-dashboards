-- Month over Month usage change — one row per customer + product.
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
MonthlyLatestReport AS (
    SELECT
        ca.company_name,
        ca.account_id,
        strftime('%Y-%m', rc.report_date) AS report_month,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rc.report_date >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY ca.company_name, ca.account_id, strftime('%Y-%m', rc.report_date), rcp.product
),
MonthlyProductUsage AS (
    SELECT
        mlr.company_name,
        mlr.report_month,
        mlr.product,
        MAX(mlr.latest_report_date) AS latest_report_date,
        SUM(rcp.amount) AS used_clients,
        SUM(rcp.exceeded_amount) AS exceeded_clients
    FROM MonthlyLatestReport mlr
    INNER JOIN report_clients rc
        ON rc.account_id = mlr.account_id
        AND rc.report_date = mlr.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = mlr.product
    GROUP BY mlr.company_name, mlr.report_month, mlr.product
),
Ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY company_name, product ORDER BY report_month DESC) AS rn
    FROM MonthlyProductUsage
)
SELECT
    curr.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = curr.company_name) AS "Account IDs",
    CASE curr.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
    END AS "Product",
    curr.report_month AS "Latest Month",
    curr.latest_report_date AS "Latest Report Date",
    COALESCE(prev.used_clients, 0) AS "Previous Month Used",
    curr.used_clients AS "Latest Month Used",
    curr.used_clients - COALESCE(prev.used_clients, 0) AS "Change",
    ROUND(
        100.0 * (curr.used_clients - COALESCE(prev.used_clients, 0)) / NULLIF(prev.used_clients, 0),
        1
    ) AS "Change %",
    curr.exceeded_clients AS "Latest Exceeded",
    CASE
        WHEN prev.used_clients IS NULL THEN 'First Month in Range'
        WHEN curr.used_clients < prev.used_clients * 0.8 THEN 'Drop Over 20% — Review'
        WHEN curr.used_clients > prev.used_clients * 1.2 THEN 'Spike Over 20% — Review'
        WHEN curr.exceeded_clients > 0 THEN 'Exceeded Clients — Review'
        ELSE 'Stable'
    END AS "Alert"
FROM Ranked curr
LEFT JOIN Ranked prev
    ON prev.company_name = curr.company_name
    AND prev.product = curr.product
    AND prev.rn = 2
WHERE curr.rn = 1
ORDER BY curr.company_name, curr.product
