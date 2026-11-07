SELECT
    COALESCE(MAX(current_contract_start_date), MAX(contract_start_date)) AS "Contract Start Date",
    MAX(current_contract_end_date) AS "Contract End Date",
    CASE
        WHEN COALESCE(MAX(current_contract_start_date), MAX(contract_start_date)) IS NOT NULL
            AND MAX(current_contract_end_date) IS NOT NULL
        THEN ROUND(
            ((julianday('now') - julianday(COALESCE(MAX(current_contract_start_date), MAX(contract_start_date))))
             /
             (julianday(MAX(current_contract_end_date)) - julianday(COALESCE(MAX(current_contract_start_date), MAX(contract_start_date)))))
            * 100,
            2
        ) || '%'
        ELSE NULL
    END AS "Days Since Contract",
    COALESCE(MAX(partner), 'N/A') AS "Selling Channel/Partner"
FROM companies
WHERE name = '${company_name}'
    AND account_id IS NOT NULL
GROUP BY name
ORDER BY name ASC;
