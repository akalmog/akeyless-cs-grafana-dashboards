-- Top 5 object types by net growth across the last 3 completed calendar months.
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
MonthlyDates AS (
    SELECT DISTINCT
        ca.account_id,
        strftime('%Y-%m', ro.report_date) AS report_month,
        MAX(ro.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_objects ro ON ro.account_id = ca.account_id
    WHERE strftime('%Y-%m', ro.report_date) IN (SELECT report_month FROM CalendarMonths)
    GROUP BY ca.account_id, strftime('%Y-%m', ro.report_date)
),
MonthlyObjectData AS (
    SELECT
        md.report_month,
        ro.object_type,
        SUM(ro.amount) AS amount
    FROM MonthlyDates md
    INNER JOIN report_objects ro ON ro.account_id = md.account_id
        AND ro.report_date = md.latest_report_date
    WHERE ro.amount > 0
      AND ro.object_type != 'auth_method'
    GROUP BY md.report_month, ro.object_type
),
Aggregated AS (
    SELECT
        mod.object_type,
        wb.start_month,
        wb.end_month,
        COALESCE(MAX(CASE WHEN mod.report_month = wb.start_month THEN mod.amount END), 0) AS start_count,
        COALESCE(MAX(CASE WHEN mod.report_month = wb.end_month THEN mod.amount END), 0) AS end_count
    FROM MonthlyObjectData mod
    CROSS JOIN WindowBounds wb
    GROUP BY mod.object_type, wb.start_month, wb.end_month
),
changes AS (
    SELECT
        agg.object_type,
        agg.start_month,
        agg.end_month,
        agg.start_count,
        agg.end_count,
        agg.end_count - agg.start_count AS absolute_change,
        ROUND(
            100.0 * (agg.end_count - agg.start_count) / NULLIF(agg.start_count, 0),
            1
        ) AS change_pct
    FROM Aggregated agg
    WHERE agg.end_count - agg.start_count > 0
)
SELECT
    object_type AS "Object Type",
    start_month || ' → ' || end_month AS "Period",
    CAST(start_count AS TEXT) || ' → ' || CAST(end_count AS TEXT) AS "Count",
    absolute_change AS "Change"
FROM changes
ORDER BY absolute_change DESC
LIMIT 5
