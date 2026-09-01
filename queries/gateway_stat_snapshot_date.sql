-- Latest gateway-related ObjectsReport date for the selected account(s).
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
SELECT COALESCE(MAX(ro.report_date), 'No gateway data') AS value
FROM CompanyAccounts ca
INNER JOIN report_objects ro ON ro.account_id = ca.account_id
WHERE {gateway_any_match}
