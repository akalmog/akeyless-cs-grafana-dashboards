-- Access type inventory per customer: one row per auth method, aggregated across SM/SRA/PWM.
-- Net change across the last 3 completed calendar months (excludes current incomplete month).
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
MonthlyLatestReport AS (
    SELECT
        ca.company_name,
        ca.account_id,
        strftime('%Y-%m', rc.report_date) AS report_month,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    WHERE strftime('%Y-%m', rc.report_date) IN (SELECT report_month FROM CalendarMonths)
    GROUP BY ca.company_name, ca.account_id, strftime('%Y-%m', rc.report_date)
),
AccessTypeUsage AS (
    SELECT
        mlr.company_name,
        mlr.report_month,
        rc.access_type,
        SUM(rcp.amount) AS used_in_limit,
        SUM(rcp.amount + COALESCE(rcp.exceeded_amount, 0)) AS total_clients
    FROM MonthlyLatestReport mlr
    INNER JOIN report_clients rc
        ON rc.account_id = mlr.account_id
        AND rc.report_date = mlr.latest_report_date
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
    GROUP BY mlr.company_name, mlr.report_month, rc.access_type
),
StartMonthUsage AS (
    SELECT company_name, access_type,
        SUM(used_in_limit) AS used_in_limit,
        SUM(total_clients) AS total_clients
    FROM AccessTypeUsage atu
    INNER JOIN WindowStartMonth wsm ON wsm.report_month = atu.report_month
    GROUP BY company_name, access_type
),
EndMonthUsage AS (
    SELECT company_name, access_type,
        SUM(used_in_limit) AS used_in_limit,
        SUM(total_clients) AS total_clients
    FROM AccessTypeUsage atu
    INNER JOIN LastFullMonth lfm ON lfm.report_month = atu.report_month
    GROUP BY company_name, access_type
),
Combined AS (
    SELECT DISTINCT company_name, access_type
    FROM AccessTypeUsage
    WHERE COALESCE(used_in_limit, 0) > 0 OR COALESCE(total_clients, 0) > 0
)
SELECT
    cb.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = cb.company_name) AS "Account IDs",
    CASE cb.access_type
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
        ELSE COALESCE(cb.access_type, 'Unknown')
    END AS "Access Type",
    (SELECT start_month FROM WindowBounds) || ' → ' || (SELECT end_month FROM WindowBounds) AS "Period",
    CAST(COALESCE(start_u.used_in_limit, 0) AS TEXT) || ' → ' || CAST(COALESCE(end_u.used_in_limit, 0) AS TEXT) AS "Used Clients",
    CAST(COALESCE(start_u.total_clients, 0) AS TEXT) || ' → ' || CAST(COALESCE(end_u.total_clients, 0) AS TEXT) AS "Total Clients including Exceeding",
    COALESCE(end_u.total_clients, 0) AS "End Total",
    COALESCE(end_u.total_clients, 0) - COALESCE(start_u.total_clients, 0) AS "Change"
FROM Combined cb
LEFT JOIN StartMonthUsage start_u
    ON start_u.company_name = cb.company_name
    AND start_u.access_type = cb.access_type
LEFT JOIN EndMonthUsage end_u
    ON end_u.company_name = cb.company_name
    AND end_u.access_type = cb.access_type
ORDER BY cb.company_name, COALESCE(end_u.total_clients, 0) DESC, "Access Type"
