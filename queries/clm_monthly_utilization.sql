-- CLM monthly utilization from certificate_analysis reports (matches original CLM Usage chart).
WITH CompanyData AS (
    SELECT DISTINCT c.name AS company_name, LOWER(c.account_id) AS account_key
    FROM companies c
    WHERE {company_filter}
),
{purchased_by_company}
DateRange AS (
    SELECT {time_range_start} AS range_start
),
CertificateDaily AS (
    SELECT
        cd.company_name,
        cd.account_key,
        strftime('%Y-%m', r.report_date) AS report_month,
        date(r.report_date) AS report_date,
        CASE
            WHEN (COALESCE(r.ca_self_signed, 0) - COALESCE(r.risk_expired, 0)) < 0 THEN 0
            ELSE (COALESCE(r.ca_self_signed, 0) - COALESCE(r.risk_expired, 0))
        END AS daily_certs
    FROM CompanyData cd
    INNER JOIN reports r ON LOWER(r.account_id) = cd.account_key
    WHERE r.report_type = 'certificate_analysis'
      AND date(r.report_date) >= (SELECT range_start FROM DateRange)
),
DailyMax AS (
    SELECT company_name, account_key, report_month, report_date,
        MAX(daily_certs) AS daily_max
    FROM CertificateDaily
    GROUP BY company_name, account_key, report_month, report_date
),
MonthlyMax AS (
    SELECT company_name, account_key, report_month,
        MAX(daily_max) AS product_used
    FROM DailyMax
    GROUP BY company_name, account_key, report_month
),
AggregatedByCompany AS (
    SELECT company_name, report_month,
        SUM(product_used) AS product_used_total
    FROM MonthlyMax
    GROUP BY company_name, report_month
),
FinalData AS (
    SELECT abc.company_name, abc.report_month,
        CASE
            WHEN pbc.clients_purchased <= 0 THEN NULL
            WHEN pbc.clients_purchased IN (999, 99999) THEN NULL
            ELSE ROUND(abc.product_used_total * 100.0 / pbc.clients_purchased, 1)
        END AS util_pct
    FROM AggregatedByCompany abc
    INNER JOIN PurchasedByCompany pbc ON pbc.company_name = abc.company_name
)
SELECT
    company_name AS "Customer",
    {avg_expr} AS "Avg (Last 3M)",
    {pivot_cols}
FROM FinalData
GROUP BY company_name
ORDER BY {order_by}
