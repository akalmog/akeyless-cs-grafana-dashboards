-- Objects snapshot by customer: latest report, key object types aggregated across account IDs.
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
LatestReportPerAccount AS (
    SELECT
        ca.company_name,
        ca.account_id,
        MAX(ro.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_objects ro ON ro.account_id = ca.account_id
    WHERE date(ro.report_date) >= {period_date_cutoff}
    GROUP BY ca.company_name, ca.account_id
),
ObjectCounts AS (
    SELECT
        lr.company_name,
        lr.account_id,
        strftime('%Y-%m', lr.latest_report_date) AS report_month,
        lr.latest_report_date,
        SUM(CASE WHEN ro.object_type LIKE '%static_secret%' THEN ro.amount ELSE 0 END) AS static_secret,
        SUM(CASE WHEN ro.object_type LIKE '%dynamic_secret%' THEN ro.amount ELSE 0 END) AS dynamic_secret,
        SUM(CASE WHEN ro.object_type LIKE '%rotated_secret%' THEN ro.amount ELSE 0 END) AS rotated_secret,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method%' AND ro.object_type NOT LIKE '%auth_method_%' THEN ro.amount ELSE 0 END) AS auth_method,
        SUM(CASE WHEN ro.object_type LIKE '%certificate%' THEN ro.amount ELSE 0 END) AS certificate,
        SUM(CASE WHEN ro.object_type LIKE '%target%' THEN ro.amount ELSE 0 END) AS target,
        SUM(CASE WHEN ro.object_type LIKE '%access_role%' AND ro.object_type NOT LIKE '%access_role_rules%' THEN ro.amount ELSE 0 END) AS access_role,
        SUM(CASE WHEN ro.object_type LIKE '%classic_key%' THEN ro.amount ELSE 0 END) AS classic_key,
        SUM(CASE WHEN ro.object_type LIKE '%rsa_key%' THEN ro.amount ELSE 0 END) AS rsa_key
    FROM LatestReportPerAccount lr
    INNER JOIN report_objects ro
        ON ro.account_id = lr.account_id
        AND ro.report_date = lr.latest_report_date
    GROUP BY lr.company_name, lr.account_id, lr.latest_report_date
)
SELECT
    company_name AS "Customer",
    COUNT(DISTINCT account_id) AS "Accounts",
    GROUP_CONCAT(DISTINCT account_id) AS "Account IDs",
    MAX(report_month) AS "Latest Month",
    MAX(latest_report_date) AS "Latest Report Date",
    SUM(static_secret) AS "Static Secret",
    SUM(dynamic_secret) AS "Dynamic Secret",
    SUM(rotated_secret) AS "Rotated Secret",
    SUM(auth_method) AS "Auth Method",
    SUM(certificate) AS "Certificate",
    SUM(target) AS "Target",
    SUM(access_role) AS "Access Role",
    SUM(classic_key) AS "Classic Key",
    SUM(rsa_key) AS "RSA Key"
FROM ObjectCounts
GROUP BY company_name
ORDER BY company_name
