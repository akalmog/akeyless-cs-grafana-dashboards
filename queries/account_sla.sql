SELECT DISTINCT account_support_level
FROM companies
WHERE name = '${company_name}'
LIMIT 1;
