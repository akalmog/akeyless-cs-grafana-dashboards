SELECT
    cl.common_name AS "Certificate",
    cl.not_after AS "Expires",
    cl.risk_level AS "Risk"
FROM report_certificate_lines cl
JOIN reports r ON r.id = cl.report_id
WHERE (
    '${account_id:raw}' IN ('All', '%', '$__all')
    OR LOWER('${account_id:raw}') = 'all'
    OR cl.account_id IN (${account_id:sqlstring})
    OR cl.account_id = '${account_id}'
)
  AND cl.risk_level IN ('critical', 'expired', 'warning')
  AND r.report_date = (
    SELECT MAX(r2.report_date)
    FROM reports r2
    WHERE r2.account_id = cl.account_id
      AND r2.report_type = 'certificate_analysis'
  )
ORDER BY cl.not_after ASC
