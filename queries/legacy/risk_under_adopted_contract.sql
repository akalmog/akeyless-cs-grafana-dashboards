-- Adoption status for SM / SRA / PM: always one row per product with risk flag.
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
LatestReportDate AS (
    SELECT
        ca.account_id,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rc.report_date >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY ca.account_id, rcp.product
),
ProductUsage AS (
    SELECT
        lrd.account_id,
        lrd.product,
        lrd.latest_report_date,
        SUM(rcp.amount) AS used_clients
    FROM LatestReportDate lrd
    INNER JOIN report_clients rc
        ON rc.account_id = lrd.account_id
        AND rc.report_date = lrd.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = lrd.product
    GROUP BY lrd.account_id, lrd.product, lrd.latest_report_date
),
CompanyInfo AS (
    SELECT
        ca.account_id,
        MAX(c.current_contract_start_date) AS current_contract_start_date,
        MAX(c.clients_sm) AS clients_sm,
        MAX(c.clients_sra) AS clients_sra,
        MAX(c.clients_pm) AS clients_pm
    FROM CompanyAccounts ca
    INNER JOIN companies c ON c.account_id = ca.account_id
    GROUP BY ca.account_id
)
SELECT
    c.name AS "Customer",
    c.account_id AS "Account ID",
    CASE p.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
    END AS "Product",
    COALESCE(ci.current_contract_start_date, 'N/A') AS "Contract Start",
    CASE
        WHEN ci.current_contract_start_date IS NULL OR ci.current_contract_start_date = '' THEN NULL
        ELSE CAST(julianday('now') - julianday(substr(ci.current_contract_start_date, 1, 10)) AS INTEGER)
    END AS "Days Since Contract Start",
    CASE p.product
        WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
        WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
        WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
    END AS "Purchased",
    COALESCE(pu.used_clients, 0) AS "Used",
    CASE
        WHEN CASE p.product
            WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
        END IN (0, 999, 99999) THEN NULL
        WHEN pu.used_clients IS NULL THEN NULL
        ELSE ROUND(
            100.0 * pu.used_clients / CASE p.product
                WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
                WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
                WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
            END,
            1
        )
    END AS "Usage %",
    CASE
        WHEN ci.current_contract_start_date IS NULL OR ci.current_contract_start_date = '' THEN 'Contract Start Unknown'
        WHEN julianday('now') - julianday(substr(ci.current_contract_start_date, 1, 10)) < 90 THEN 'Early Contract — Monitor'
        WHEN pu.used_clients IS NULL THEN 'No Client Reports in Range'
        WHEN CASE p.product
            WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
        END IN (0, 999, 99999) THEN 'No Purchased Limit'
        WHEN pu.used_clients < CASE p.product
            WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
        END * 0.3 THEN 'Under-Adopted — Contract Active 90+ Days'
        ELSE 'On Track'
    END AS "Risk Status"
FROM CompanyAccounts ca
CROSS JOIN Products p
INNER JOIN CompanyInfo ci ON ci.account_id = ca.account_id
INNER JOIN companies c ON c.account_id = ca.account_id
LEFT JOIN ProductUsage pu ON pu.account_id = ca.account_id AND pu.product = p.product
WHERE CASE p.product
    WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
    WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
    WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
END > 0
ORDER BY c.name, p.product
