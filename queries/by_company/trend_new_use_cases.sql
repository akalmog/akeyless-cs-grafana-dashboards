-- New secret types or auth methods per customer: one row per type — net change across the last 3 completed calendar months.
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
    SELECT strftime('%Y-%m', date('now', 'start of month', '-1 month')) AS report_month
),
WindowStartMonth AS (
    SELECT strftime('%Y-%m', date((SELECT report_month FROM LastFullMonth) || '-01', '-2 month')) AS report_month
),
WindowBounds AS (
    SELECT
        (SELECT report_month FROM WindowStartMonth) AS start_month,
        (SELECT report_month FROM LastFullMonth) AS end_month
),
CalendarMonths AS (
    SELECT (SELECT report_month FROM WindowStartMonth) AS report_month
    UNION ALL
    SELECT strftime('%Y-%m', date((SELECT report_month FROM LastFullMonth) || '-01', '-1 month'))
    UNION ALL
    SELECT (SELECT report_month FROM LastFullMonth) AS report_month
),
MonthlyDates AS (
    SELECT DISTINCT
        ca.company_name,
        ca.account_id,
        strftime('%Y-%m', ro.report_date) AS report_month,
        MAX(ro.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_objects ro ON ro.account_id = ca.account_id
    WHERE strftime('%Y-%m', ro.report_date) IN (SELECT report_month FROM CalendarMonths)
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
        OR (
          ro.object_type LIKE '%password%'
          AND ro.object_type NOT LIKE '%static_secret%'
          AND ro.object_type NOT LIKE '%dynamic_secret%'
          AND ro.object_type NOT LIKE '%rotated_secret%'
        )
      )
    GROUP BY md.company_name, md.report_month, md.latest_report_date, ro.object_type
),
WindowObjectData AS (
    SELECT mod.company_name, mod.report_month, mod.object_type, mod.amount
    FROM MonthlyObjectData mod
),
Aggregated AS (
    SELECT
        wod.company_name,
        wod.object_type,
        wb.start_month,
        wb.end_month,
        COALESCE(MAX(CASE WHEN wod.report_month = wb.start_month THEN wod.amount END), 0) AS start_count,
        COALESCE(MAX(CASE WHEN wod.report_month = wb.end_month THEN wod.amount END), 0) AS end_count
    FROM WindowObjectData wod
    CROSS JOIN WindowBounds wb
    GROUP BY wod.company_name, wod.object_type, wb.start_month, wb.end_month
),
Changes AS (
    SELECT
        agg.company_name,
        agg.start_month,
        agg.end_month,
        agg.object_type,
        agg.start_count AS previous_count,
        agg.end_count AS current_count,
        agg.end_count - agg.start_count AS net_change,
        CASE
            WHEN agg.object_type LIKE '%auth_method_%' THEN 'Authentication Method'
            WHEN agg.object_type LIKE '%password%'
              AND agg.object_type NOT LIKE '%static_secret%'
              AND agg.object_type NOT LIKE '%dynamic_secret%'
              AND agg.object_type NOT LIKE '%rotated_secret%' THEN 'Password Management'
            WHEN agg.object_type LIKE '%secret%'
              OR agg.object_type LIKE '%_key%'
              OR agg.object_type LIKE '%cert_issuer%'
              OR agg.object_type LIKE '%code_sign%'
              OR agg.object_type LIKE '%document_sign%' THEN 'Secret Type'
            ELSE 'Other'
        END AS category,
        CASE
            WHEN agg.object_type LIKE '%auth_method_api_key%' THEN 'Auth Method API Key'
            WHEN agg.object_type LIKE '%auth_method_universal_identity%' THEN 'Auth Method Universal Identity'
            WHEN agg.object_type LIKE '%auth_method_aws_iam%' THEN 'Auth Method AWS IAM'
            WHEN agg.object_type LIKE '%auth_method_kubernetes%' THEN 'Auth Method Kubernetes'
            WHEN agg.object_type LIKE '%auth_method_azure_ad%' THEN 'Auth Method Azure AD'
            WHEN agg.object_type LIKE '%auth_method_gcp%' THEN 'Auth Method GCP'
            WHEN agg.object_type LIKE '%auth_method_saml%' THEN 'Auth Method SAML'
            WHEN agg.object_type LIKE '%auth_method_oidc%' THEN 'Auth Method OIDC'
            WHEN agg.object_type LIKE '%auth_method_jwt%' THEN 'Auth Method JWT'
            WHEN agg.object_type LIKE '%auth_method_ldap%' THEN 'Auth Method LDAP'
            WHEN agg.object_type LIKE '%managed_password%' THEN 'Managed Password'
            WHEN agg.object_type LIKE '%personal_password%' THEN 'Personal Password'
            WHEN agg.object_type LIKE '%shared_password%' THEN 'Shared Password'
            WHEN agg.object_type LIKE '%password%'
              AND agg.object_type NOT LIKE '%secret%' THEN 'Password'
            WHEN agg.object_type LIKE '%static_secret%' THEN 'Static Secret'
            WHEN agg.object_type LIKE '%dynamic_secret%' THEN 'Dynamic Secret'
            WHEN agg.object_type LIKE '%rotated_secret%' THEN 'Rotated Secret'
            WHEN agg.object_type LIKE '%classic_key%' THEN 'Classic Key'
            WHEN agg.object_type LIKE '%rsa_key%' THEN 'RSA Key'
            WHEN agg.object_type LIKE '%aes_key%' THEN 'AES Key'
            WHEN agg.object_type LIKE '%dfc_key%' THEN 'DFC Key'
            WHEN agg.object_type LIKE '%pki_cert_issuer%' THEN 'PKI Cert Issuer'
            WHEN agg.object_type LIKE '%ssh_cert_issuer%' THEN 'SSH Cert Issuer'
            ELSE agg.object_type
        END AS friendly_name
    FROM Aggregated agg
)
SELECT
    ch.company_name AS "Customer",
    ch.friendly_name AS "Type",
    ch.start_month || ' → ' || ch.end_month AS "Period",
    CAST(ch.previous_count AS TEXT) || ' → ' || CAST(ch.current_count AS TEXT) AS "Start → End",
    ch.current_count AS "Count",
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
ORDER BY ch.company_name, ch.current_count DESC, ch.net_change DESC, ch.friendly_name
