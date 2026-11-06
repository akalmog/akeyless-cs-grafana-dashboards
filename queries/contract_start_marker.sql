SELECT
    CAST(strftime('%s', substr(c.current_contract_start_date, 1, 10)) AS INTEGER) AS time,
    c.account_id,
    COALESCE(
        CAST(c.{purchased_col} AS INTEGER),
        (SELECT MAX(COALESCE(rcp.amount, 0))
         FROM report_clients rc
         JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
         WHERE rc.account_id = c.account_id AND rcp.product = '{product}'),
        1000
    ) AS "Contract Start"
FROM companies c
WHERE c.name = '${company_name}'
  AND c.current_contract_start_date IS NOT NULL
  AND c.current_contract_start_date != ''
  AND date(substr(c.current_contract_start_date, 1, 10)) >= {period_date_cutoff}
  AND date(substr(c.current_contract_start_date, 1, 10)) <= date('now')
  AND (
    ('${account_id:raw}' IN ('All', '%', '$__all') OR LOWER('${account_id:raw}') = 'all' OR c.account_id = '${account_id}')
  )
