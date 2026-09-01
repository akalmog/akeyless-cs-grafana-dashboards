-- Legacy monthly utilization % (used only, latest report per month).
WITH CompanyAccounts AS (
    SELECT DISTINCT account_id
    FROM companies
    WHERE name = '${company_name}'
      AND account_id IS NOT NULL AND account_id != ''
      AND account_id = '${account_id}'
),
AccountHubSpotData AS (
    SELECT ca.account_id, c.{purchased_col}
    FROM CompanyAccounts ca
    INNER JOIN companies c ON ca.account_id = c.account_id
    WHERE c.name = '${company_name}'
),
AccountDateRanges AS (
    SELECT ca.account_id,
        CASE
            WHEN '${period_months}' LIKE '3%' THEN strftime('%Y-%m-%d', 'now', '-3 months')
            WHEN '${period_months}' LIKE '12%' THEN strftime('%Y-%m-%d', 'now', '-12 months')
            ELSE strftime('%Y-%m-%d', 'now', '-12 months')
        END AS range_start_date,
        strftime('%Y-%m-%d', 'now') AS range_end_date
    FROM CompanyAccounts ca
),
MonthsWithData AS (
    SELECT DISTINCT
        adr.account_id,
        strftime('%Y-%m', r.report_date) AS report_month,
        strftime('%Y-%m-01', r.report_date) AS month_start_date,
        date(strftime('%Y-%m-01', r.report_date), '+1 month', '-1 day') AS month_end_date
    FROM AccountDateRanges adr
    INNER JOIN reports r ON r.account_id = adr.account_id AND r.report_type = 'ObjectsReport'
    WHERE date(r.report_date) >= date(adr.range_start_date)
      AND date(r.report_date) <= date(adr.range_end_date)
),
OneReportPerAccountDate AS (
    SELECT account_id, date(report_date) AS report_date, MAX(id) AS report_id
    FROM reports
    WHERE report_type = 'ObjectsReport'
      AND account_id IN (SELECT account_id FROM CompanyAccounts)
    GROUP BY account_id, date(report_date)
),
LatestReportDatePerMonth AS (
    SELECT
        LOWER(m.account_id) AS account_key,
        m.report_month,
        m.month_start_date,
        m.month_end_date,
        MAX(r.report_date) AS latest_report_date
    FROM MonthsWithData m
    INNER JOIN reports r ON r.account_id = m.account_id AND r.report_type = 'ObjectsReport'
        AND date(r.report_date) >= m.month_start_date
        AND date(r.report_date) <= m.month_end_date
    GROUP BY LOWER(m.account_id), m.report_month, m.month_start_date, m.month_end_date
),
SingleReportId AS (
    SELECT
        l.report_month,
        MAX(orad.report_id) AS report_id
    FROM LatestReportDatePerMonth l
    INNER JOIN OneReportPerAccountDate orad
        ON LOWER(orad.account_id) = l.account_key
        AND orad.report_date = date(l.latest_report_date)
    GROUP BY l.report_month, l.latest_report_date
),
MonthlyUsed AS (
    SELECT
        s.report_month,
        COALESCE(SUM(rcp.amount), 0) AS used_amount
    FROM SingleReportId s
    LEFT JOIN report_clients rc ON rc.report_id = s.report_id
    LEFT JOIN report_clients_product_info rcp
        ON rc.id = rcp.report_client_id AND rcp.product = '{product}'
    GROUP BY s.report_month
)
SELECT
    mu.report_month AS "Month",
    ROUND(
        100.0 * mu.used_amount / NULLIF(CAST(MAX(ahsd.{purchased_col}) AS INTEGER), 0),
        1
    ) AS "Utilization %"
FROM MonthlyUsed mu
CROSS JOIN AccountHubSpotData ahsd
GROUP BY mu.report_month, mu.used_amount
ORDER BY mu.report_month
