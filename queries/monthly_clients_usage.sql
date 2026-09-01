-- One report per account per month (latest ObjectsReport) to avoid double-counting daily rows.
WITH CompanyAccounts AS (
    SELECT DISTINCT account_id, name AS company_name
    FROM companies
    WHERE name = '${company_name}'
      AND account_id IS NOT NULL AND account_id != ''
      AND (
        '${account_id:raw}' IN ('All', '%', '$__all')
        OR LOWER('${account_id:raw}') = 'all'
        OR account_id = '${account_id}'
      )
),
AccountHubSpotData AS (
    SELECT ca.account_id, ca.company_name, c.{purchased_col}, c.current_contract_start_date
    FROM CompanyAccounts ca
    INNER JOIN companies c ON ca.account_id = c.account_id
    WHERE c.name = '${company_name}'
),
AccountDateRanges AS (
    SELECT ca.account_id,
        {time_range_start} AS range_start_date,
        {time_range_end} AS range_end_date
    FROM CompanyAccounts ca
    INNER JOIN AccountHubSpotData ahsd ON ca.account_id = ahsd.account_id
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
        l.account_key,
        l.report_month,
        l.month_start_date,
        l.month_end_date,
        l.latest_report_date,
        MAX(orad.report_id) AS report_id
    FROM LatestReportDatePerMonth l
    INNER JOIN OneReportPerAccountDate orad
        ON LOWER(orad.account_id) = l.account_key
        AND orad.report_date = date(l.latest_report_date)
    GROUP BY l.account_key, l.report_month, l.month_start_date, l.month_end_date, l.latest_report_date
),
MonthlyReportData AS (
    SELECT
        (SELECT account_id FROM reports WHERE id = s.report_id) AS account_id,
        s.report_month,
        s.month_start_date,
        s.month_end_date,
        COALESCE(SUM(rcp.amount), 0) AS used_amount,
        COALESCE(SUM(rcp.exceeded_amount), 0) AS exceeded_amount
    FROM SingleReportId s
    LEFT JOIN report_clients rc ON rc.report_id = s.report_id
    LEFT JOIN report_clients_product_info rcp
        ON rc.id = rcp.report_client_id AND rcp.product = '{product}'
    GROUP BY s.report_id, s.report_month, s.month_start_date, s.month_end_date
),
MonthlyReportSummary AS (
    SELECT
        m.account_id,
        m.report_month,
        MIN(r.report_date) AS earliest_report_date,
        MAX(r.report_date) AS latest_report_date
    FROM MonthsWithData m
    LEFT JOIN reports r ON r.account_id = m.account_id AND r.report_type = 'ObjectsReport'
        AND date(r.report_date) >= m.month_start_date
        AND date(r.report_date) <= m.month_end_date
    GROUP BY m.account_id, m.report_month
)
SELECT
    CAST(strftime('%s', MIN(mrd.month_start_date)) AS INTEGER) AS time,
    mrd.report_month,
    SUM(mrd.used_amount) AS "Used Clients",
    SUM(mrd.exceeded_amount) AS "Exceeded Clients",
    CASE
        WHEN CAST(COALESCE(MAX(ahsd.{purchased_col}), '0') AS INTEGER) IN (999, 99999) THEN NULL
        ELSE MAX(CAST(COALESCE(ahsd.{purchased_col}, '0') AS INTEGER))
    END AS "Purchased Clients",
    MIN(mrs.earliest_report_date) AS report_date_start,
    MAX(mrs.latest_report_date) AS report_date_end
FROM MonthlyReportData mrd
INNER JOIN AccountHubSpotData ahsd ON mrd.account_id = ahsd.account_id
LEFT JOIN MonthlyReportSummary mrs
    ON mrd.account_id = mrs.account_id AND mrd.report_month = mrs.report_month
GROUP BY mrd.report_month
ORDER BY time ASC
