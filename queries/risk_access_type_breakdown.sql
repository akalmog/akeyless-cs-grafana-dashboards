-- Access type breakdown: one row per auth method (aggregated across SM/SRA/PWM).
-- Snapshot for the last completed calendar month (excludes current incomplete month).
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
LastFullMonth AS (
    SELECT strftime('%Y-%m', 'now', 'start of month', '-1 month') AS report_month
),
LatestReportDate AS (
    SELECT
        ca.account_id,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    INNER JOIN LastFullMonth lfm ON lfm.report_month = strftime('%Y-%m', rc.report_date)
    WHERE rcp.product IN ('sm', 'sra', 'apm')
    GROUP BY ca.account_id
)
SELECT
    c.account_id AS "Account ID",
    CASE rc.access_type
        WHEN 'api_key' THEN 'API Key'
        WHEN 'aws_iam' THEN 'AWS IAM'
        WHEN 'saml2' THEN 'SAML'
        WHEN 'universal_identity' THEN 'Universal Identity'
        WHEN 'k8s' THEN 'K8s'
        WHEN 'ldap' THEN 'LDAP'
        WHEN 'oidc' THEN 'OIDC'
        WHEN 'jwt' THEN 'JWT'
        WHEN 'azure_ad' THEN 'Azure AD'
        WHEN 'gcp' THEN 'GCP'
        ELSE COALESCE(rc.access_type, 'Unknown')
    END AS "Access Type",
    (SELECT report_month FROM LastFullMonth) AS "Month",
    SUM(rcp.amount) AS "Used Clients",
    SUM(COALESCE(rcp.exceeded_amount, 0)) AS "Exceeded Clients",
    SUM(rcp.amount + COALESCE(rcp.exceeded_amount, 0)) AS "Total Clients"
FROM LatestReportDate lrd
INNER JOIN report_clients rc
    ON rc.account_id = lrd.account_id
    AND rc.report_date = lrd.latest_report_date
INNER JOIN report_clients_product_info rcp
    ON rcp.report_client_id = rc.id
    AND rcp.product IN ('sm', 'sra', 'apm')
INNER JOIN companies c ON c.account_id = lrd.account_id
GROUP BY c.account_id, rc.access_type
HAVING SUM(rcp.amount) > 0 OR SUM(COALESCE(rcp.exceeded_amount, 0)) > 0
ORDER BY "Total Clients" DESC, "Access Type"
