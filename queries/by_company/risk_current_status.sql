-- Latest client usage vs purchased limit for the last completed calendar month (by customer).
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
      AND rc.report_date >= {period_date_cutoff}
    GROUP BY ca.company_name, ca.account_id, strftime('%Y-%m', rc.report_date), rcp.product
),
ProductUsage AS (
    SELECT
        mlr.company_name,
        mlr.product,
        mlr.report_month,
        SUM(rcp.amount) AS used_clients,
        SUM(rcp.exceeded_amount) AS exceeded_clients,
        MAX(CASE mlr.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
        END) AS purchased
    FROM MonthlyLatestReport mlr
    INNER JOIN LastFullMonth lfm ON lfm.report_month = mlr.report_month
    INNER JOIN report_clients rc
        ON rc.account_id = mlr.account_id
        AND rc.report_date = mlr.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = mlr.product
    INNER JOIN companies c ON c.account_id = mlr.account_id
    GROUP BY mlr.company_name, mlr.product, mlr.report_month
)
SELECT
    pu.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = pu.company_name) AS "Account IDs",
    CASE pu.product
        WHEN 'sm' THEN 'SM'
        WHEN 'sra' THEN 'SRA'
        WHEN 'apm' THEN 'PWM'
    END AS "Product",
    pu.report_month AS "Month",
    pu.purchased AS "Purchased",
    pu.used_clients AS "Used Clients",
    pu.exceeded_clients AS "Exceeded",
    pu.used_clients + pu.exceeded_clients AS "Total Clients including Exceeding",
    CASE
        WHEN pu.exceeded_clients > 0 THEN 'Exceeded Clients Detected'
        WHEN pu.purchased NOT IN (0, 999, 99999)
          AND (pu.used_clients + pu.exceeded_clients) > pu.purchased THEN 'Over Purchased Limit'
        WHEN pu.purchased NOT IN (0, 999, 99999)
          AND (pu.used_clients + pu.exceeded_clients) >= pu.purchased * 0.9 THEN 'Near Limit (90%+)'
        WHEN pu.purchased NOT IN (0, 999, 99999)
          AND (pu.used_clients + pu.exceeded_clients) < pu.purchased * 0.3 THEN 'Under-Adopted (<30%)'
        ELSE 'Within Normal Range'
    END AS "Risk Status"
FROM ProductUsage pu
ORDER BY pu.company_name, pu.product
