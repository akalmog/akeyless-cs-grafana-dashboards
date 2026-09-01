-- Adoption status: yearly usage vs annual purchased limit from current contract year start.
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
LastFullMonth AS (
    SELECT strftime('%Y-%m', 'now', 'start of month', '-1 month') AS report_month
),
CompanyInfo AS (
    SELECT
        ca.account_id,
        MAX(c.current_contract_start_date) AS current_contract_start_date,
        MAX(c.contract_start_date) AS contract_start_date,
        MAX(c.current_contract_end_date) AS current_contract_end_date,
        MAX(CAST(c.clients_sm AS INTEGER)) AS clients_sm,
        MAX(CAST(c.clients_sra AS INTEGER)) AS clients_sra,
        MAX(CAST(c.clients_pm AS INTEGER)) AS clients_pm
    FROM CompanyAccounts ca
    INNER JOIN companies c ON c.account_id = ca.account_id
    GROUP BY ca.account_id
),
ContractYear AS (
    SELECT
        ci.account_id,
        ci.current_contract_start_date,
        CASE
            WHEN ci.current_contract_start_date IS NULL OR ci.current_contract_start_date = '' THEN NULL
            WHEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr(ci.current_contract_start_date, 1, 10))) > date('now')
                THEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr(ci.current_contract_start_date, 1, 10)), '-1 year')
            ELSE date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr(ci.current_contract_start_date, 1, 10)))
        END AS contract_year_start
    FROM CompanyInfo ci
),
MonthlyLatestReport AS (
    SELECT
        ca.account_id,
        strftime('%Y-%m', r.report_date) AS report_month,
        MAX(r.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN reports r ON r.account_id = ca.account_id AND r.report_type = 'ObjectsReport'
    INNER JOIN ContractYear cy ON cy.account_id = ca.account_id
    INNER JOIN LastFullMonth lfm ON 1 = 1
    WHERE cy.contract_year_start IS NOT NULL
      AND strftime('%Y-%m', r.report_date) >= strftime('%Y-%m', cy.contract_year_start)
      AND strftime('%Y-%m', r.report_date) <= lfm.report_month
    GROUP BY ca.account_id, strftime('%Y-%m', r.report_date)
),
OneReportPerAccountDate AS (
    SELECT account_id, date(report_date) AS report_date, MAX(id) AS report_id
    FROM reports
    WHERE report_type = 'ObjectsReport'
      AND account_id IN (SELECT account_id FROM CompanyAccounts)
    GROUP BY account_id, date(report_date)
),
SingleReportId AS (
    SELECT
        mlr.account_id,
        mlr.report_month,
        MAX(orad.report_id) AS report_id
    FROM MonthlyLatestReport mlr
    INNER JOIN OneReportPerAccountDate orad
        ON orad.account_id = mlr.account_id
        AND orad.report_date = date(mlr.latest_report_date)
    GROUP BY mlr.account_id, mlr.report_month
),
YearlyUsage AS (
    SELECT
        sri.account_id,
        rcp.product,
        SUM(rcp.amount) AS used_in_limit,
        SUM(rcp.exceeded_amount) AS exceeded_clients,
        SUM(rcp.amount + rcp.exceeded_amount) AS total_clients
    FROM SingleReportId sri
    INNER JOIN report_clients rc ON rc.report_id = sri.report_id
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product IN ('sm', 'sra', 'apm')
    GROUP BY sri.account_id, rcp.product
)
SELECT
    c.name AS "Customer",
    c.account_id AS "Account ID",
    CASE p.product
        WHEN 'sm' THEN 'SM'
        WHEN 'sra' THEN 'SRA'
        WHEN 'apm' THEN 'PWM'
    END AS "Product",
    COALESCE(ci.current_contract_start_date, 'N/A') AS "Contract Start",
    CASE
        WHEN COALESCE(ci.current_contract_start_date, ci.contract_start_date) IS NULL
            OR ci.current_contract_end_date IS NULL
            OR ci.current_contract_end_date = '' THEN NULL
        ELSE ROUND(
            ((julianday('now') - julianday(COALESCE(ci.current_contract_start_date, ci.contract_start_date)))
             / NULLIF(
                julianday(ci.current_contract_end_date)
                - julianday(COALESCE(ci.current_contract_start_date, ci.contract_start_date)),
                0
             )) * 100,
            2
        ) || '%'
    END AS "Days Since Contract",
    CASE p.product
        WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER) * 12
        WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER) * 12
        WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER) * 12
    END AS "Purchased (Annual)",
    COALESCE(yu.used_in_limit, 0) AS "Used (Contract Year)",
    COALESCE(yu.exceeded_clients, 0) AS "Exceeded (Contract Year)",
    COALESCE(yu.total_clients, 0) AS "Total (Contract Year)",
    CASE
        WHEN ci.current_contract_start_date IS NULL OR ci.current_contract_start_date = '' THEN 'Contract Start Unknown'
        WHEN cy.contract_year_start IS NULL THEN 'Contract Start Unknown'
        WHEN julianday('now') - julianday(cy.contract_year_start) < 90 THEN 'Early Contract Year — Monitor'
        WHEN yu.total_clients IS NULL THEN 'No Client Reports in Contract Year'
        WHEN CASE p.product
            WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
        END IN (0, 999, 99999) THEN 'No Purchased Limit'
        WHEN yu.total_clients < CASE p.product
            WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER) * 12
            WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER) * 12
            WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER) * 12
        END * 0.3 THEN 'Under-Adopted — Contract Year Active 90+ Days'
        ELSE 'On Track'
    END AS "Risk Status"
FROM CompanyAccounts ca
CROSS JOIN Products p
INNER JOIN CompanyInfo ci ON ci.account_id = ca.account_id
INNER JOIN ContractYear cy ON cy.account_id = ca.account_id
INNER JOIN companies c ON c.account_id = ca.account_id
LEFT JOIN YearlyUsage yu ON yu.account_id = ca.account_id AND yu.product = p.product
WHERE CASE p.product
    WHEN 'sm' THEN CAST(ci.clients_sm AS INTEGER)
    WHEN 'sra' THEN CAST(ci.clients_sra AS INTEGER)
    WHEN 'apm' THEN CAST(ci.clients_pm AS INTEGER)
END > 0
ORDER BY c.name, p.product
