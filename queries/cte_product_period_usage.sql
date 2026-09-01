-- Shared CTEs: period usage from ObjectsReport (one report/account/date, latest per month).
-- Matches original "By Customer" SM Usage gauge / purchased-vs-used stat panels.
WITH CompanyAccounts AS (
    SELECT DISTINCT account_id, name AS company_name
    FROM companies
    WHERE {company_accounts_where}
),
AccountHubSpotData AS (
    SELECT ca.account_id, ca.company_name, c.{purchased_col}
    FROM CompanyAccounts ca
    INNER JOIN companies c ON ca.account_id = c.account_id
    WHERE {hubspot_company_filter}
),
AccountDateRanges AS (
    SELECT ca.account_id,
        {time_range_start} AS range_start_date,
        {time_range_end} AS range_end_date
    FROM CompanyAccounts ca
    INNER JOIN companies c ON ca.account_id = c.account_id
    WHERE {hubspot_company_filter}
),
OneReportPerAccountDate AS (
    SELECT account_id, date(report_date) AS report_date, MAX(id) AS report_id
    FROM reports
    WHERE report_type = 'ObjectsReport'
      AND account_id IN (SELECT account_id FROM CompanyAccounts)
    GROUP BY account_id, date(report_date)
),
MonthsWithData AS (
    SELECT DISTINCT
        LOWER(adr.account_id) AS account_key,
        strftime('%Y-%m', r.report_date) AS report_month,
        strftime('%Y-%m-01', r.report_date) AS month_start_date,
        date(strftime('%Y-%m-01', r.report_date), '+1 month', '-1 day') AS month_end_date
    FROM AccountDateRanges adr
    INNER JOIN reports r ON r.account_id = adr.account_id AND r.report_type = 'ObjectsReport'
    WHERE date(r.report_date) >= date(adr.range_start_date)
      AND date(r.report_date) <= date(adr.range_end_date)
),
LatestReportDatePerMonth AS (
    SELECT
        m.account_key,
        m.report_month,
        m.month_start_date,
        m.month_end_date,
        MAX(r.report_date) AS latest_report_date
    FROM MonthsWithData m
    INNER JOIN reports r ON LOWER(r.account_id) = m.account_key AND r.report_type = 'ObjectsReport'
        AND date(r.report_date) >= m.month_start_date
        AND date(r.report_date) <= m.month_end_date
    GROUP BY m.account_key, m.report_month, m.month_start_date, m.month_end_date
),
SingleReportId AS (
    SELECT
        l.account_key,
        l.report_month,
        MAX(orad.report_id) AS report_id
    FROM LatestReportDatePerMonth l
    INNER JOIN OneReportPerAccountDate orad
        ON LOWER(orad.account_id) = l.account_key
        AND orad.report_date = date(l.latest_report_date)
    GROUP BY l.account_key, l.report_month
),
MonthlyReportData AS (
    SELECT
        s.account_key,
        s.report_month,
        COALESCE(SUM(rcp.amount), 0) AS product_amount,
        COALESCE(SUM(rcp.exceeded_amount), 0) AS product_exceeded_amount
    FROM SingleReportId s
    LEFT JOIN report_clients rc ON rc.report_id = s.report_id
    LEFT JOIN report_clients_product_info rcp
        ON rc.id = rcp.report_client_id AND rcp.product = '{product}'
    GROUP BY s.account_key, s.report_month
),
PerLogicalAccountTotals AS (
    SELECT
        account_key,
        SUM(product_amount) AS product_amount,
        SUM(product_exceeded_amount) AS product_exceeded_amount
    FROM MonthlyReportData
    GROUP BY account_key
),
PeriodTotals AS (
    SELECT
        COALESCE(SUM(product_amount), 0) AS used_total,
        COALESCE(SUM(product_exceeded_amount), 0) AS exceeded_total,
        COALESCE(SUM(product_amount + product_exceeded_amount), 0) AS used_plus_exceeded_total
    FROM PerLogicalAccountTotals
),
TimeRangeMonths AS (
    SELECT {time_range_month_count} AS month_count
),
PurchasedSummary AS (
    SELECT
        (SELECT CAST(COALESCE({purchased_col}, '0') AS INTEGER)
         FROM AccountHubSpotData
         WHERE CAST(COALESCE({purchased_col}, '0') AS INTEGER) NOT IN (999, 99999)
         ORDER BY account_id
         LIMIT 1) AS purchased_limit,
        (SELECT MAX(CASE WHEN CAST(COALESCE({purchased_col}, '0') AS INTEGER) IN (999, 99999) THEN 1 ELSE 0 END)
         FROM AccountHubSpotData) AS is_unlimited
),
PeriodCapacity AS (
    SELECT
        ps.purchased_limit,
        ps.is_unlimited,
        trm.month_count,
        ps.purchased_limit * trm.month_count AS purchased_monthly_total
    FROM PurchasedSummary ps
    CROSS JOIN TimeRangeMonths trm
)
