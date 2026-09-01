-- Objects stacked bar: latest report per month, wide object-type columns (matches production dashboard).
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
AccountDateRanges AS (
    SELECT ca.account_id,
        {time_range_start} AS range_start_date,
        {time_range_end} AS range_end_date
    FROM CompanyAccounts ca
),
MonthlyDates AS (
    SELECT DISTINCT
        adr.account_id,
        strftime('%Y-%m', ro.report_date) AS report_month,
        strftime('%Y-%m-01', ro.report_date) AS month_start_date
    FROM AccountDateRanges adr
    INNER JOIN report_objects ro ON ro.account_id = adr.account_id
    WHERE date(ro.report_date) >= adr.range_start_date
      AND date(ro.report_date) <= adr.range_end_date
),
LatestReportPerMonth AS (
    SELECT
        md.account_id,
        md.report_month,
        md.month_start_date,
        MAX(ro.report_date) AS latest_report_date
    FROM MonthlyDates md
    INNER JOIN report_objects ro ON ro.account_id = md.account_id
        AND strftime('%Y-%m', ro.report_date) = md.report_month
    GROUP BY md.account_id, md.report_month, md.month_start_date
),
MonthlyObjectData AS (
    SELECT
        lrpm.account_id,
        lrpm.report_month,
        ro.object_type,
        SUM(ro.amount) AS amount
    FROM LatestReportPerMonth lrpm
    INNER JOIN report_objects ro ON ro.account_id = lrpm.account_id
        AND ro.report_date = lrpm.latest_report_date
    WHERE ro.amount > 0
    GROUP BY lrpm.account_id, lrpm.report_month, ro.object_type
)
SELECT
    mod.report_month AS month,
    SUM(CASE WHEN mod.object_type LIKE '%access_role%' AND mod.object_type NOT LIKE '%access_role_rules%' THEN mod.amount ELSE 0 END) AS "Access Role",
    SUM(CASE WHEN mod.object_type LIKE '%aes_key%' THEN mod.amount ELSE 0 END) AS "AES Key",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method%' AND mod.object_type NOT LIKE '%auth_method_%' THEN mod.amount ELSE 0 END) AS "Auth Method",
    SUM(CASE WHEN mod.object_type LIKE '%certified_automation%' THEN mod.amount ELSE 0 END) AS "Certified Automation",
    SUM(CASE WHEN mod.object_type LIKE '%classic_key%' THEN mod.amount ELSE 0 END) AS "Classic Key",
    SUM(CASE WHEN mod.object_type LIKE '%code_sign%' THEN mod.amount ELSE 0 END) AS "Code Sign",
    SUM(CASE WHEN mod.object_type LIKE '%document_sign%' THEN mod.amount ELSE 0 END) AS "Document Sign",
    SUM(CASE WHEN mod.object_type LIKE '%dynamic_secret%' THEN mod.amount ELSE 0 END) AS "Dynamic Secret",
    SUM(CASE WHEN mod.object_type LIKE '%pki_cert_issuer%' THEN mod.amount ELSE 0 END) AS "PKI Cert Issuer",
    SUM(CASE WHEN mod.object_type LIKE '%rotated_secret%' THEN mod.amount ELSE 0 END) AS "Rotated Secret",
    SUM(CASE WHEN mod.object_type LIKE '%rsa_key%' THEN mod.amount ELSE 0 END) AS "RSA Key",
    SUM(CASE WHEN mod.object_type LIKE '%ssh_cert_issuer%' THEN mod.amount ELSE 0 END) AS "SSH Cert Issuer",
    SUM(CASE WHEN mod.object_type LIKE '%static_secret%' THEN mod.amount ELSE 0 END) AS "Static Secret",
    SUM(CASE WHEN mod.object_type LIKE '%sub_claim%' THEN mod.amount ELSE 0 END) AS "Sub Claim",
    SUM(CASE WHEN mod.object_type LIKE '%target%' THEN mod.amount ELSE 0 END) AS "Target",
    SUM(CASE WHEN mod.object_type LIKE '%tokenizer%' THEN mod.amount ELSE 0 END) AS "Tokenizer",
    SUM(CASE WHEN mod.object_type LIKE '%noti_forwarder%' THEN mod.amount ELSE 0 END) AS "Notification Forwarder",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_aws_iam%' THEN mod.amount ELSE 0 END) AS "Auth Method AWS IAM",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_api_key%' THEN mod.amount ELSE 0 END) AS "Auth Method API Key",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_kubernetes%' THEN mod.amount ELSE 0 END) AS "Auth Method Kubernetes",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_saml%' THEN mod.amount ELSE 0 END) AS "Auth Method SAML",
    SUM(CASE WHEN mod.object_type LIKE '%certificate%' THEN mod.amount ELSE 0 END) AS "Certificate",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_azure_ad%' THEN mod.amount ELSE 0 END) AS "Auth Method Azure AD",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_universal_identity%' THEN mod.amount ELSE 0 END) AS "Auth Method Universal Identity",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_jwt%' THEN mod.amount ELSE 0 END) AS "Auth Method JWT",
    SUM(CASE WHEN mod.object_type LIKE '%dfc_key%' THEN mod.amount ELSE 0 END) AS "DFC Key",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_email_pass%' THEN mod.amount ELSE 0 END) AS "Auth Method Email/Pass",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_oidc%' THEN mod.amount ELSE 0 END) AS "Auth Method OIDC",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_ldap%' THEN mod.amount ELSE 0 END) AS "Auth Method LDAP",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_gcp%' THEN mod.amount ELSE 0 END) AS "Auth Method GCP",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_cert%' THEN mod.amount ELSE 0 END) AS "Auth Method Cert",
    SUM(CASE WHEN mod.object_type LIKE '%transaction_per_client%' THEN mod.amount ELSE 0 END) AS "Transaction Per Client",
    SUM(CASE WHEN mod.object_type LIKE '%transactions_per_client_minutes%' THEN mod.amount ELSE 0 END) AS "Transactions Per Client Minutes",
    SUM(CASE WHEN mod.object_type LIKE '%multi_cloud_kms%' THEN mod.amount ELSE 0 END) AS "Multi Cloud KMS",
    SUM(CASE WHEN mod.object_type LIKE '%external_secrets_manager%' THEN mod.amount ELSE 0 END) AS "External Secrets Manager",
    SUM(CASE WHEN mod.object_type LIKE '%transactions_per_account_daily%' THEN mod.amount ELSE 0 END) AS "Transactions Per Account Daily",
    SUM(CASE WHEN mod.object_type LIKE '%oidc_client%' THEN mod.amount ELSE 0 END) AS "OIDC Client",
    SUM(CASE WHEN mod.object_type LIKE '%group%' THEN mod.amount ELSE 0 END) AS "Group",
    SUM(CASE WHEN mod.object_type LIKE '%auth_method_oci%' THEN mod.amount ELSE 0 END) AS "Auth Method OCI"
FROM MonthlyObjectData mod
INNER JOIN CompanyAccounts ca ON mod.account_id = ca.account_id
GROUP BY mod.report_month
ORDER BY mod.report_month
