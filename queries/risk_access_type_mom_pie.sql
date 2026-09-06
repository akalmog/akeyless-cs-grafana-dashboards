-- Access type mix at end of 3-month MoM window (donut chart, single-account).
-- Net change across the last 3 completed calendar months (excludes current incomplete month).
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
        ca.account_id,
        strftime('%Y-%m', rc.report_date) AS report_month,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    WHERE strftime('%Y-%m', rc.report_date) IN (SELECT report_month FROM CalendarMonths)
    GROUP BY ca.account_id, strftime('%Y-%m', rc.report_date)
),
AccessTypeUsage AS (
    SELECT
        mlr.account_id,
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
    GROUP BY mlr.account_id, mlr.report_month, rc.access_type
),
StartMonthUsage AS (
    SELECT account_id, access_type, used_in_limit, total_clients
    FROM AccessTypeUsage atu
    INNER JOIN WindowStartMonth wsm ON wsm.report_month = atu.report_month
),
EndMonthUsage AS (
    SELECT account_id, access_type, used_in_limit, total_clients
    FROM AccessTypeUsage atu
    INNER JOIN LastFullMonth lfm ON lfm.report_month = atu.report_month
),
Combined AS (
    SELECT DISTINCT account_id, access_type
    FROM AccessTypeUsage
    WHERE COALESCE(used_in_limit, 0) > 0 OR COALESCE(total_clients, 0) > 0
),
DetailRows AS (
    SELECT
        c.account_id AS account_id,
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
        END AS access_type_label,
        (SELECT start_month FROM WindowBounds) || ' → ' || (SELECT end_month FROM WindowBounds) AS period_label,
        COALESCE(start_u.used_in_limit, 0) AS start_used,
        COALESCE(end_u.used_in_limit, 0) AS end_used,
        COALESCE(start_u.total_clients, 0) AS start_total,
        COALESCE(end_u.total_clients, 0) AS end_total
    FROM Combined cb
    INNER JOIN companies c ON c.account_id = cb.account_id
    LEFT JOIN StartMonthUsage start_u
        ON start_u.account_id = cb.account_id
        AND start_u.access_type = cb.access_type
    LEFT JOIN EndMonthUsage end_u
        ON end_u.account_id = cb.account_id
        AND end_u.access_type = cb.access_type
)
SELECT
    access_type_label AS "Access Type",
    end_total AS "Count"
FROM DetailRows
WHERE end_total > 0
ORDER BY end_total DESC
