-- Peak daily exceeded clients for SM, SRA, and PM only.
SELECT
    CASE e.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
        ELSE e.product
    END AS "Product",
    e.access_id AS "Access ID",
    e.highest_daily AS "Peak Daily",
    e.highest_daily_date AS "Peak Date"
FROM report_exceeded_clients_full_info e
JOIN reports r ON r.id = e.report_id
WHERE e.product IN ('sm', 'sra', 'apm')
  AND (
    '${account_id:raw}' IN ('All', '%', '$__all')
    OR LOWER('${account_id:raw}') = 'all'
    OR e.account_id IN (${account_id:sqlstring})
    OR e.account_id = '${account_id}'
  )
ORDER BY e.product, e.highest_daily DESC
