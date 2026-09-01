-- Bar gauge: static vs dynamic+rotated secret counts.
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
ObjectCounts AS (
    SELECT
        SUM(CASE WHEN ro.object_type LIKE '%static_secret%' THEN ro.amount ELSE 0 END) AS static_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%dynamic_secret%' THEN ro.amount ELSE 0 END) AS dynamic_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%rotated_secret%' THEN ro.amount ELSE 0 END) AS rotated_secrets
    FROM LatestObjectReport lor
    INNER JOIN report_objects ro
        ON ro.account_id = lor.account_id
        AND ro.report_date = lor.latest_report_date
)
SELECT
    static_secrets AS "Static Secrets",
    dynamic_secrets + rotated_secrets AS "Dynamic + Rotated"
FROM ObjectCounts
