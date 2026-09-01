-- Days since last report per report type (ObjectsReport drives usage metrics).
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
)
SELECT
    CASE r.report_type
        WHEN 'ObjectsReport' THEN 'Objects Report (Usage & Objects)'
        WHEN 'clients_report' THEN 'Clients Report'
        WHEN 'objects_report' THEN 'Objects Report (Legacy)'
        ELSE r.report_type
    END AS "Report Type",
    MAX(r.report_date) AS "Last Report Date",
    CAST(julianday('now') - julianday(MAX(r.report_date)) AS INTEGER) AS "Days Since Last Report",
    CASE
        WHEN MAX(r.report_date) IS NULL THEN 'No Reports Found'
        WHEN julianday('now') - julianday(MAX(r.report_date)) > 35 THEN 'Stale — Follow Up Required'
        WHEN julianday('now') - julianday(MAX(r.report_date)) > 14 THEN 'Aging — Monitor'
        ELSE 'Current'
    END AS "Status"
FROM CompanyAccounts ca
LEFT JOIN reports r ON r.account_id = ca.account_id
WHERE r.report_type IN ('ObjectsReport', 'clients_report', 'objects_report')
GROUP BY r.report_type
ORDER BY "Days Since Last Report" DESC
