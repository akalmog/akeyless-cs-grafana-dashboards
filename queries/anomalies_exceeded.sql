SELECT
    e.access_id AS "Access ID",
    e.product AS "Product",
    e.highest_daily AS "Peak Daily",
    e.highest_daily_date AS "Peak Date"
FROM report_exceeded_clients_full_info e
JOIN reports r ON r.id = e.report_id
WHERE (
    '${account_id:raw}' IN ('All', '%', '$__all')
    OR LOWER('${account_id:raw}') = 'all'
    OR e.account_id IN (${account_id:sqlstring})
    OR e.account_id = '${account_id}'
)
ORDER BY e.highest_daily DESC
LIMIT 50
