-- New secret types or auth methods per customer (0 → small count = pilot/testing).
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
MonthlyDates AS (
    SELECT DISTINCT
        ca.company_name,
        ca.account_id,
        strftime('%Y-%m', ro.report_date) AS report_month,
        MAX(ro.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_objects ro ON ro.account_id = ca.account_id
    WHERE date(ro.report_date) >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY ca.company_name, ca.account_id, strftime('%Y-%m', ro.report_date)
),
MonthlyObjectData AS (
    SELECT
        md.company_name,
        md.report_month,
        md.latest_report_date,
        ro.object_type,
        SUM(ro.amount) AS amount
    FROM MonthlyDates md
    INNER JOIN report_objects ro ON ro.account_id = md.account_id
        AND ro.report_date = md.latest_report_date
    WHERE ro.amount >= 0
      AND (
        ro.object_type LIKE '%secret%'
        OR ro.object_type LIKE '%auth_method_%'
        OR ro.object_type LIKE '%classic_key%'
        OR ro.object_type LIKE '%rsa_key%'
        OR ro.object_type LIKE '%aes_key%'
        OR ro.object_type LIKE '%dfc_key%'
        OR ro.object_type LIKE '%cert_issuer%'
        OR ro.object_type LIKE '%code_sign%'
        OR ro.object_type LIKE '%document_sign%'
      )
    GROUP BY md.company_name, md.report_month, md.latest_report_date, ro.object_type
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY company_name, object_type ORDER BY report_month DESC) AS rn
    FROM MonthlyObjectData
),
Changes AS (
    SELECT
        curr.company_name,
        curr.report_month,
        curr.latest_report_date,
        curr.object_type,
        curr.amount AS current_count,
        COALESCE(prev.amount, 0) AS previous_count,
        curr.amount - COALESCE(prev.amount, 0) AS net_change,
        CASE
            WHEN curr.object_type LIKE '%auth_method_%' THEN 'Authentication Method'
            WHEN curr.object_type LIKE '%secret%'
              OR curr.object_type LIKE '%_key%'
              OR curr.object_type LIKE '%cert_issuer%'
              OR curr.object_type LIKE '%code_sign%'
              OR curr.object_type LIKE '%document_sign%' THEN 'Secret Type'
            ELSE 'Other'
        END AS category,
        CASE
            WHEN curr.object_type LIKE '%auth_method_api_key%' THEN 'Auth Method API Key'
            WHEN curr.object_type LIKE '%auth_method_universal_identity%' THEN 'Auth Method Universal Identity'
            WHEN curr.object_type LIKE '%auth_method_aws_iam%' THEN 'Auth Method AWS IAM'
            WHEN curr.object_type LIKE '%auth_method_kubernetes%' THEN 'Auth Method Kubernetes'
            WHEN curr.object_type LIKE '%auth_method_azure_ad%' THEN 'Auth Method Azure AD'
            WHEN curr.object_type LIKE '%auth_method_gcp%' THEN 'Auth Method GCP'
            WHEN curr.object_type LIKE '%auth_method_saml%' THEN 'Auth Method SAML'
            WHEN curr.object_type LIKE '%auth_method_oidc%' THEN 'Auth Method OIDC'
            WHEN curr.object_type LIKE '%auth_method_jwt%' THEN 'Auth Method JWT'
            WHEN curr.object_type LIKE '%auth_method_ldap%' THEN 'Auth Method LDAP'
            WHEN curr.object_type LIKE '%static_secret%' THEN 'Static Secret'
            WHEN curr.object_type LIKE '%dynamic_secret%' THEN 'Dynamic Secret'
            WHEN curr.object_type LIKE '%rotated_secret%' THEN 'Rotated Secret'
            WHEN curr.object_type LIKE '%classic_key%' THEN 'Classic Key'
            WHEN curr.object_type LIKE '%rsa_key%' THEN 'RSA Key'
            WHEN curr.object_type LIKE '%aes_key%' THEN 'AES Key'
            WHEN curr.object_type LIKE '%dfc_key%' THEN 'DFC Key'
            WHEN curr.object_type LIKE '%pki_cert_issuer%' THEN 'PKI Cert Issuer'
            WHEN curr.object_type LIKE '%ssh_cert_issuer%' THEN 'SSH Cert Issuer'
            ELSE curr.object_type
        END AS friendly_name
    FROM ranked curr
    LEFT JOIN ranked prev
        ON prev.company_name = curr.company_name
        AND prev.object_type = curr.object_type
        AND prev.rn = 2
    WHERE curr.rn = 1
)
SELECT
    ch.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = ch.company_name) AS "Account IDs",
    ch.category AS "Category",
    ch.friendly_name AS "Type",
    ch.latest_report_date AS "Latest Report Date",
    ch.report_month AS "Latest Month",
    ch.previous_count AS "Previous Month Count",
    ch.current_count AS "Current Count",
    ch.net_change AS "Net Change",
    CASE
        WHEN ch.previous_count = 0 AND ch.current_count BETWEEN 1 AND 25
            THEN 'New Use Case — Customer May Be Testing (Meeting Opportunity)'
        WHEN ch.previous_count = 0 AND ch.current_count > 25
            THEN 'New Type — Recently Adopted at Scale'
        WHEN ch.net_change BETWEEN 1 AND 25 AND ch.previous_count > 0
            THEN 'Expanding Pilot — Discuss Scaling'
        ELSE 'Emerging — Monitor Adoption'
    END AS "Adoption Signal"
FROM Changes ch
WHERE (
    (ch.previous_count = 0 AND ch.current_count > 0)
    OR (ch.net_change BETWEEN 1 AND 25 AND ch.current_count <= 25)
)
ORDER BY
    ch.company_name,
    CASE ch.category WHEN 'Authentication Method' THEN 1 WHEN 'Secret Type' THEN 2 ELSE 3 END,
    ch.net_change DESC,
    ch.friendly_name
