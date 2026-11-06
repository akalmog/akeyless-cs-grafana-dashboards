-- CLM monthly usage from certificate_analysis (same certificate count as the CLM utilization table).
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
CertificateDaily AS (
    SELECT
        strftime('%Y-%m', r.report_date) AS report_month,
        strftime('%Y-%m-01', r.report_date) AS month_start_date,
        LOWER(r.account_id) AS account_key,
        date(r.report_date) AS report_date,
        CASE
            WHEN (COALESCE(r.ca_self_signed, 0) - COALESCE(r.risk_expired, 0)) < 0 THEN 0
            ELSE (COALESCE(r.ca_self_signed, 0) - COALESCE(r.risk_expired, 0))
        END AS daily_certs
    FROM reports r
    INNER JOIN CompanyAccounts ca ON LOWER(r.account_id) = LOWER(ca.account_id)
    WHERE r.report_type = 'certificate_analysis'
      AND date(r.report_date) >= {time_range_start}
      AND date(r.report_date) <= {time_range_end}
),
DailyMax AS (
    SELECT report_month, month_start_date, account_key, report_date, MAX(daily_certs) AS daily_max
    FROM CertificateDaily
    GROUP BY report_month, month_start_date, account_key, report_date
),
MonthlyMax AS (
    SELECT report_month, MIN(month_start_date) AS month_start_date, account_key, MAX(daily_max) AS used_amount
    FROM DailyMax
    GROUP BY report_month, account_key
)
SELECT
    CAST(strftime('%s', MIN(month_start_date)) AS INTEGER) AS time,
    SUM(used_amount) AS "Used Clients",
    0 AS "Exceeded Clients",
    (
        SELECT CASE WHEN lim IN (999, 99999) THEN NULL ELSE lim END
        FROM (
            SELECT CAST(COALESCE(ahsd.{purchased_col}, '0') AS INTEGER) AS lim
            FROM AccountHubSpotData ahsd
            ORDER BY
                CASE WHEN CAST(COALESCE(ahsd.{purchased_col}, '0') AS INTEGER) > 0 THEN 0 ELSE 1 END,
                ahsd.account_id
            LIMIT 1
        )
    ) AS "Purchased Clients"
FROM MonthlyMax
GROUP BY report_month
ORDER BY time ASC
