-- Canonical monthly client usage: latest report_clients date per month per product.
-- Matches SM / SRA / PM "Used" stat panels (NOT ObjectsReport aggregation).
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
        mlr.report_month,
        mlr.product,
        mlr.latest_report_date,
        SUM(rcp.amount) AS used_clients,
        SUM(rcp.exceeded_amount) AS exceeded_clients
    FROM MonthlyLatestReport mlr
    INNER JOIN report_clients rc
        ON rc.account_id = mlr.account_id
        AND rc.report_date = mlr.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = mlr.product
    GROUP BY mlr.report_month, mlr.product, mlr.latest_report_date
)
SELECT * FROM MonthlyProductUsage
