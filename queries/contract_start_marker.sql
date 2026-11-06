-- One contract-start dot, on the same HubSpot account the purchased line uses.
SELECT
    CAST(strftime('%s', substr(c.current_contract_start_date, 1, 10)) AS INTEGER) AS time,
    CASE
        WHEN CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) IN (999, 99999) THEN NULL
        ELSE CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER)
    END AS "Contract Start"
FROM companies c
WHERE c.name = '${company_name}'
  AND c.account_id IS NOT NULL
  AND c.account_id != ''
  AND c.current_contract_start_date IS NOT NULL
  AND c.current_contract_start_date != ''
  AND date(substr(c.current_contract_start_date, 1, 10)) >= {time_range_start}
  AND date(substr(c.current_contract_start_date, 1, 10)) <= {time_range_end}
  AND (
    '${account_id:raw}' IN ('All', '%', '$__all')
    OR LOWER('${account_id:raw}') = 'all'
    OR c.account_id = '${account_id}'
  )
ORDER BY
    CASE WHEN CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) > 0 THEN 0 ELSE 1 END,
    c.account_id
LIMIT 1
