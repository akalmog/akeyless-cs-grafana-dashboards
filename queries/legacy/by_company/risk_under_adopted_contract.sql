-- Adoption status — one row per customer + product.
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
Products AS (
    SELECT 'sm' AS product
    UNION ALL SELECT 'sra'
    UNION ALL SELECT 'apm'
),
LatestReportDate AS (
    SELECT
        ca.company_name,
        ca.account_id,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rc.report_date >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY ca.company_name, ca.account_id, rcp.product
),
ProductUsage AS (
    SELECT
        lrd.company_name,
        lrd.product,
        SUM(rcp.amount) AS used_clients
    FROM LatestReportDate lrd
    INNER JOIN report_clients rc
        ON rc.account_id = lrd.account_id
        AND rc.report_date = lrd.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = lrd.product
    GROUP BY lrd.company_name, lrd.product
),
CompanyInfo AS (
    SELECT
        ca.company_name,
        MIN(c.current_contract_start_date) AS current_contract_start_date,
        SUM(CAST(c.clients_sm AS INTEGER)) AS clients_sm,
        SUM(CAST(c.clients_sra AS INTEGER)) AS clients_sra,
        SUM(CAST(c.clients_pm AS INTEGER)) AS clients_pm
    FROM CompanyAccounts ca
    INNER JOIN companies c ON c.account_id = ca.account_id
    GROUP BY ca.company_name
)
SELECT
    ci.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = ci.company_name) AS "Account IDs",
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
        WHEN 'sm' THEN ci.clients_sm
        WHEN 'sra' THEN ci.clients_sra
        WHEN 'apm' THEN ci.clients_pm
    END AS "Purchased",
    COALESCE(pu.used_clients, 0) AS "Used",
    CASE
        WHEN CASE p.product
            WHEN 'sm' THEN ci.clients_sm
            WHEN 'sra' THEN ci.clients_sra
            WHEN 'apm' THEN ci.clients_pm
        END IN (0, 999, 99999) THEN NULL
        WHEN pu.used_clients IS NULL THEN NULL
        ELSE ROUND(
            100.0 * pu.used_clients / CASE p.product
                WHEN 'sm' THEN ci.clients_sm
                WHEN 'sra' THEN ci.clients_sra
                WHEN 'apm' THEN ci.clients_pm
            END,
            1
        )
    END AS "Usage %",
    CASE
        WHEN ci.current_contract_start_date IS NULL OR ci.current_contract_start_date = '' THEN 'Contract Start Unknown'
        WHEN julianday('now') - julianday(substr(ci.current_contract_start_date, 1, 10)) < 90 THEN 'Early Contract — Monitor'
        WHEN pu.used_clients IS NULL THEN 'No Client Reports in Range'
        WHEN CASE p.product
            WHEN 'sm' THEN ci.clients_sm
            WHEN 'sra' THEN ci.clients_sra
            WHEN 'apm' THEN ci.clients_pm
        END IN (0, 999, 99999) THEN 'No Purchased Limit'
        WHEN pu.used_clients < CASE p.product
            WHEN 'sm' THEN ci.clients_sm
            WHEN 'sra' THEN ci.clients_sra
            WHEN 'apm' THEN ci.clients_pm
        END * 0.3 THEN 'Under-Adopted — Contract Active 90+ Days'
        ELSE 'On Track'
    END AS "Risk Status"
FROM CompanyInfo ci
CROSS JOIN Products p
LEFT JOIN ProductUsage pu ON pu.company_name = ci.company_name AND pu.product = p.product
WHERE CASE p.product
    WHEN 'sm' THEN ci.clients_sm
    WHEN 'sra' THEN ci.clients_sra
    WHEN 'apm' THEN ci.clients_pm
END > 0
ORDER BY ci.company_name, p.product
