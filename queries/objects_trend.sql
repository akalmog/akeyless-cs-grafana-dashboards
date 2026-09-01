-- Object trend alerts: net change across the last 3 completed calendar months + stale objects.
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
    SELECT strftime('%Y-%m', 'now', 'start of month', '-1 month') AS report_month
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
stale_objects AS (
    SELECT
        mod.object_type,
        wb.start_month,
        wb.end_month,
        MAX(mod.amount) AS flat_count
    FROM MonthlyObjectData mod
    CROSS JOIN WindowBounds wb
    GROUP BY mod.object_type, wb.start_month, wb.end_month
    HAVING COUNT(DISTINCT mod.report_month) = 3
      AND MIN(mod.amount) = MAX(mod.amount)
      AND MAX(mod.amount) > 0
),
window_alerts AS (
    SELECT
        agg.object_type,
        agg.start_month,
        agg.end_month,
        agg.start_count,
        agg.end_count,
        agg.end_count - agg.start_count AS change_val,
        ROUND(100.0 * (agg.end_count - agg.start_count) / NULLIF(agg.start_count, 0), 1) AS change_pct,
        CASE
            WHEN agg.start_count = 0 AND agg.end_count > 0 THEN 'New — Review'
            WHEN agg.end_count > agg.start_count * 1.1 THEN 'Growth — Good'
            WHEN agg.end_count > agg.start_count THEN 'Stable Growth'
            WHEN agg.end_count < agg.start_count * 0.9 THEN 'Reduction — Review'
            WHEN agg.end_count < agg.start_count THEN 'Stable Decline'
            ELSE 'Stable'
        END AS trend_alert
    FROM Aggregated agg
    WHERE agg.start_count > 0 OR agg.end_count > 0
),
combined AS (
    SELECT
        object_type,
        start_month,
        end_month,
        start_count,
        end_count,
        change_val,
        change_pct,
        trend_alert,
        0 AS is_stale
    FROM window_alerts

    UNION ALL

    SELECT
        s.object_type,
        s.start_month,
        s.end_month,
        s.flat_count,
        s.flat_count,
        0,
        0.0,
        'Stale — No Growth in 3 Months',
        1
    FROM stale_objects s
    WHERE NOT EXISTS (
        SELECT 1 FROM window_alerts wa
        WHERE wa.object_type = s.object_type
          AND wa.trend_alert IN (
              'Growth — Good',
              'Stable Growth',
              'Reduction — Review',
              'Stable Decline',
              'New — Review'
          )
    )
)
SELECT
    c.object_type AS "Object Type",
    c.start_month || ' → ' || c.end_month AS "Period",
    CAST(c.start_count AS TEXT) || ' → ' || CAST(c.end_count AS TEXT) AS "Count",
    c.change_val AS "Change",
    c.change_pct AS "Change %",
    c.trend_alert AS "Trend Alert"
FROM combined c
ORDER BY c.is_stale DESC, ABS(c.change_val) DESC, c.object_type ASC
