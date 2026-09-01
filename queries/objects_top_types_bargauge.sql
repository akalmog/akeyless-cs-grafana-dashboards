-- Bar gauge: top 5 object types by count in latest month.
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
LatestReport AS (
    SELECT MAX(ro.report_date) AS latest_report_date
    FROM report_objects ro
    INNER JOIN CompanyAccounts ca ON ca.account_id = ro.account_id
),
LatestCounts AS (
    SELECT
        ro.object_type,
        SUM(ro.amount) AS amount
    FROM report_objects ro
    INNER JOIN CompanyAccounts ca ON ca.account_id = ro.account_id
    INNER JOIN LatestReport lr ON lr.latest_report_date = ro.report_date
    WHERE ro.amount > 0
    GROUP BY ro.object_type
),
top5 AS (
    SELECT object_type, amount
    FROM LatestCounts
    ORDER BY amount DESC
    LIMIT 5
)
SELECT
    MAX(CASE WHEN rn = 1 THEN amount END) AS "Largest Type",
    MAX(CASE WHEN rn = 2 THEN amount END) AS "2nd Largest",
    MAX(CASE WHEN rn = 3 THEN amount END) AS "3rd Largest",
    MAX(CASE WHEN rn = 4 THEN amount END) AS "4th Largest",
    MAX(CASE WHEN rn = 5 THEN amount END) AS "5th Largest"
FROM (
    SELECT object_type, amount,
        ROW_NUMBER() OVER (ORDER BY amount DESC) AS rn
    FROM top5
)
