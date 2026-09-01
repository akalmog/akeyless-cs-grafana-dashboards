-- Exceeded client events grouped by access type (latest report snapshot).
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
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rcp.exceeded_amount > 0
      AND rc.report_date >= {period_date_cutoff}
    GROUP BY ca.account_id
)
SELECT
    CASE rc.access_type
        WHEN 'api_key' THEN 'API Key'
        WHEN 'aws_iam' THEN 'AWS IAM'
        WHEN 'saml2' THEN 'SAML'
        WHEN 'universal_identity' THEN 'Universal Identity'
        ELSE COALESCE(rc.access_type, 'Unknown')
    END AS "Access Type",
    CASE rcp.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
    END AS "Product",
    lrd.latest_report_date AS "Report Date",
    COUNT(DISTINCT rc.id) AS "Exceeded Client Records",
    SUM(rcp.exceeded_amount) AS "Total Exceeded Amount"
FROM LatestReportDate lrd
INNER JOIN report_clients rc
    ON rc.account_id = lrd.account_id
    AND rc.report_date = lrd.latest_report_date
INNER JOIN report_clients_product_info rcp
    ON rcp.report_client_id = rc.id
    AND rcp.product IN ('sm', 'sra', 'apm')
WHERE rcp.exceeded_amount > 0
GROUP BY rc.access_type, rcp.product, lrd.latest_report_date
ORDER BY "Total Exceeded Amount" DESC
