-- Pie chart: authentication method breakdown from latest objects report (non-zero only).
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
LatestObjectReport AS (
    SELECT ro.account_id, MAX(ro.report_date) AS latest_report_date
    FROM report_objects ro
    INNER JOIN CompanyAccounts ca ON ca.account_id = ro.account_id
    GROUP BY ro.account_id
),
AuthMethodCounts AS (
    SELECT
        ro.object_type,
        SUM(ro.amount) AS amount
    FROM LatestObjectReport lor
    INNER JOIN report_objects ro
        ON ro.account_id = lor.account_id
        AND ro.report_date = lor.latest_report_date
    WHERE ro.object_type LIKE '%auth_method%'
    GROUP BY ro.object_type
    HAVING SUM(ro.amount) > 0
)
SELECT
    CASE
        WHEN object_type LIKE '%auth_method_api_key%' THEN 'API Key'
        WHEN object_type LIKE '%auth_method_kubernetes%' THEN 'Kubernetes'
        WHEN object_type LIKE '%auth_method_aws_iam%' THEN 'AWS IAM'
        WHEN object_type LIKE '%auth_method_azure_ad%' THEN 'Azure AD'
        WHEN object_type LIKE '%auth_method_gcp%' THEN 'GCP'
        WHEN object_type LIKE '%auth_method_universal_identity%' THEN 'Universal Identity'
        WHEN object_type LIKE '%auth_method_saml%' THEN 'SAML'
        WHEN object_type LIKE '%auth_method_jwt%' THEN 'JWT'
        WHEN object_type LIKE '%auth_method_oidc%' THEN 'OIDC'
        WHEN object_type LIKE '%auth_method_ldap%' THEN 'LDAP'
        WHEN object_type LIKE '%auth_method_email_pass%' THEN 'Email/Pass'
        WHEN object_type LIKE '%auth_method_cert%' THEN 'Cert'
        WHEN object_type LIKE '%auth_method_huawei%' THEN 'Huawei'
        WHEN object_type LIKE '%auth_method_oci%' THEN 'OCI'
        WHEN object_type LIKE '%auth_method%'
          AND object_type NOT LIKE '%auth_method_%' THEN 'Auth Method'
        ELSE object_type
    END AS "Auth Method",
    amount AS "Count"
FROM AuthMethodCounts
ORDER BY amount DESC
