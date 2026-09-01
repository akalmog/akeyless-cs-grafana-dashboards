-- Access type usage by customer + product (aggregated across account IDs).
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
LatestReportDate AS (
    SELECT
        ca.company_name,
        ca.account_id,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    WHERE rc.report_date >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY ca.company_name, ca.account_id
)
SELECT
    lrd.company_name AS "Customer",
    GROUP_CONCAT(DISTINCT lrd.account_id) AS "Account IDs",
    CASE rc.access_type
        WHEN 'api_key' THEN 'API Key'
        WHEN 'aws_iam' THEN 'AWS IAM'
        WHEN 'saml2' THEN 'SAML'
        WHEN 'universal_identity' THEN 'Universal Identity'
        ELSE COALESCE(rc.access_type, 'Unknown')
    END AS "Access Type",
    MAX(lrd.latest_report_date) AS "Report Date",
    CASE rcp.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
    END AS "Product",
    SUM(rcp.amount) AS "Used Clients",
    SUM(rcp.exceeded_amount) AS "Exceeded Clients"
FROM LatestReportDate lrd
INNER JOIN report_clients rc
    ON rc.account_id = lrd.account_id
    AND rc.report_date = lrd.latest_report_date
INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
WHERE rcp.product IN ('sm', 'sra', 'apm')
GROUP BY lrd.company_name, rc.access_type, rcp.product
HAVING SUM(rcp.amount) > 0 OR SUM(rcp.exceeded_amount) > 0
ORDER BY lrd.company_name, "Used Clients" DESC, "Product"
