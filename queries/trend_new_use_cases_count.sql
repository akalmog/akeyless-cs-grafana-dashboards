-- Stat: count of new use case adoption signals in latest vs previous month.
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
    GROUP BY md.report_month, ro.object_type
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY object_type ORDER BY report_month DESC) AS rn
    FROM MonthlyObjectData
),
signals AS (
    SELECT curr.object_type
    FROM ranked curr
    LEFT JOIN ranked prev ON prev.object_type = curr.object_type AND prev.rn = 2
    WHERE curr.rn = 1
      AND COALESCE(prev.amount, 0) = 0
      AND curr.amount BETWEEN 1 AND 25
)
SELECT COUNT(*) AS value FROM signals
