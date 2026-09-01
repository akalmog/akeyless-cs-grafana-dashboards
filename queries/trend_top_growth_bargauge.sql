-- Bar gauge: top 5 object types by month-over-month growth (absolute).
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
MonthlyDates AS (
    SELECT DISTINCT
        ca.account_id,
        strftime('%Y-%m', ro.report_date) AS report_month,
        MAX(ro.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_objects ro ON ro.account_id = ca.account_id
    WHERE date(ro.report_date) >= {period_date_cutoff}
    GROUP BY ca.account_id, strftime('%Y-%m', ro.report_date)
),
MonthlyObjectData AS (
    SELECT
        md.report_month,
        ro.object_type,
        SUM(ro.amount) AS amount
    FROM MonthlyDates md
    INNER JOIN report_objects ro
        ON ro.account_id = md.account_id
        AND ro.report_date = md.latest_report_date
    WHERE ro.amount > 0
    GROUP BY md.report_month, ro.object_type
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY object_type ORDER BY report_month DESC) AS rn
    FROM MonthlyObjectData
),
growth AS (
    SELECT
        curr.object_type,
        curr.amount - COALESCE(prev.amount, 0) AS absolute_change
    FROM ranked curr
    LEFT JOIN ranked prev ON prev.object_type = curr.object_type AND prev.rn = 2
    WHERE curr.rn = 1
      AND curr.amount > COALESCE(prev.amount, 0)
),
top5 AS (
    SELECT object_type, absolute_change
    FROM growth
    ORDER BY absolute_change DESC
    LIMIT 5
)
SELECT
    MAX(CASE WHEN rn = 1 THEN absolute_change END) AS "Top 1 Growth",
    MAX(CASE WHEN rn = 2 THEN absolute_change END) AS "Top 2 Growth",
    MAX(CASE WHEN rn = 3 THEN absolute_change END) AS "Top 3 Growth",
    MAX(CASE WHEN rn = 4 THEN absolute_change END) AS "Top 4 Growth",
    MAX(CASE WHEN rn = 5 THEN absolute_change END) AS "Top 5 Growth"
FROM (
    SELECT object_type, absolute_change,
        ROW_NUMBER() OVER (ORDER BY absolute_change DESC) AS rn
    FROM top5
)
