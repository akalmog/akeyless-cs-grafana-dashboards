-- Access type breakdown per customer: one row per auth method (aggregated across SM/SRA/PWM).
-- Snapshot for the last completed calendar month (excludes current incomplete month).
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
    SELECT strftime('%Y-%m', 'now', 'start of month', '-1 month') AS report_month
),
MonthlyLatestReport AS (
    SELECT
        ca.company_name,
        ca.account_id,
        (SELECT report_month FROM LastFullMonth) AS report_month,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    INNER JOIN LastFullMonth lfm ON lfm.report_month = strftime('%Y-%m', rc.report_date)
    WHERE rcp.product IN ('sm', 'sra', 'apm')
    GROUP BY ca.company_name, ca.account_id
),
LatestSnapshot AS (
    SELECT
        mlr.company_name,
        rc.access_type,
        mlr.report_month,
        SUM(rcp.amount) AS used_clients,
        SUM(COALESCE(rcp.exceeded_amount, 0)) AS exceeded_clients,
        SUM(rcp.amount + COALESCE(rcp.exceeded_amount, 0)) AS total_clients
    FROM MonthlyLatestReport mlr
    INNER JOIN report_clients rc
        ON rc.account_id = mlr.account_id
        AND rc.report_date = mlr.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product IN ('sm', 'sra', 'apm')
    GROUP BY mlr.company_name, rc.access_type, mlr.report_month
    HAVING SUM(rcp.amount) > 0 OR SUM(COALESCE(rcp.exceeded_amount, 0)) > 0
)
SELECT
    ls.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = ls.company_name) AS "Account IDs",
    CASE ls.access_type
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
        ELSE COALESCE(ls.access_type, 'Unknown')
    END AS "Access Type",
    ls.report_month AS "Month",
    ls.used_clients AS "Used Clients",
    ls.exceeded_clients AS "Exceeded Clients",
    ls.total_clients AS "Total Clients"
FROM LatestSnapshot ls
ORDER BY ls.company_name, ls.total_clients DESC, "Access Type"
