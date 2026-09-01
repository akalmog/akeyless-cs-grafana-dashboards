SELECT account_id
FROM companies
WHERE name = '${company_name}'
    AND account_id IS NOT NULL
    AND account_id != ''
ORDER BY account_id;
