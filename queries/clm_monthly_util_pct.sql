-- CLM monthly utilization % (unpivoted) from certificate_analysis reports.
WITH CompanyData AS (
    SELECT DISTINCT c.name AS company_name, LOWER(c.account_id) AS account_key,
        CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) AS clients_purchased
    FROM companies c
    WHERE {company_filter}
),
DateRange AS (
    SELECT {time_range_start} AS range_start
),
CertificateDaily AS (
    SELECT
        cd.company_name,
        cd.account_key,
        cd.clients_purchased,
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
    SELECT company_name, account_key, clients_purchased, report_month, report_date,
        MAX(daily_certs) AS daily_max
    FROM CertificateDaily
    GROUP BY company_name, account_key, clients_purchased, report_month, report_date
),
MonthlyMax AS (
    SELECT company_name, account_key, clients_purchased, report_month,
        MAX(daily_max) AS product_used
    FROM DailyMax
    GROUP BY company_name, account_key, clients_purchased, report_month
),
AggregatedByCompany AS (
    SELECT company_name, MAX(clients_purchased) AS clients_purchased, report_month,
        SUM(product_used) AS product_used_total
    FROM MonthlyMax
    GROUP BY company_name, report_month
)
SELECT
    report_month AS "Month",
    CASE
        WHEN clients_purchased <= 0 THEN NULL
        WHEN clients_purchased IN (999, 99999) THEN NULL
        ELSE ROUND(product_used_total * 100.0 / clients_purchased, 1)
    END AS "Utilization %"
FROM AggregatedByCompany
WHERE product_used_total > 0 OR clients_purchased > 0
ORDER BY report_month
