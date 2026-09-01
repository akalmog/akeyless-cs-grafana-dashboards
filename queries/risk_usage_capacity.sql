-- Bar gauge: used vs purchased limit per active product.
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
LatestReportDate AS (
    SELECT
        ca.account_id,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rc.report_date >= {period_date_cutoff}
    GROUP BY ca.account_id, rcp.product
),
ProductUsage AS (
    SELECT
        lrd.product,
        SUM(rcp.amount) AS used_clients
    FROM LatestReportDate lrd
    INNER JOIN report_clients rc
        ON rc.account_id = lrd.account_id
        AND rc.report_date = lrd.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = lrd.product
    GROUP BY lrd.product
),
CompanyInfo AS (
    SELECT
        MAX(CAST(c.clients_sm AS INTEGER)) AS clients_sm,
        MAX(CAST(c.clients_sra AS INTEGER)) AS clients_sra,
        MAX(CAST(c.clients_pm AS INTEGER)) AS clients_pm
    FROM CompanyAccounts ca
    INNER JOIN companies c ON c.account_id = ca.account_id
)
SELECT
    MAX(CASE WHEN ci.clients_sm > 0 THEN pu_sm.used_clients END) AS "SM Used",
    MAX(CASE WHEN ci.clients_sm > 0 THEN ci.clients_sm END) AS "SM Purchased",
    MAX(CASE WHEN ci.clients_sra > 0 THEN pu_sra.used_clients END) AS "SRA Used",
    MAX(CASE WHEN ci.clients_sra > 0 THEN ci.clients_sra END) AS "SRA Purchased",
    MAX(CASE WHEN ci.clients_pm > 0 THEN pu_pm.used_clients END) AS "PM Used",
    MAX(CASE WHEN ci.clients_pm > 0 THEN ci.clients_pm END) AS "PM Purchased"
FROM CompanyInfo ci
LEFT JOIN ProductUsage pu_sm ON pu_sm.product = 'sm'
LEFT JOIN ProductUsage pu_sra ON pu_sra.product = 'sra'
LEFT JOIN ProductUsage pu_pm ON pu_pm.product = 'apm'
