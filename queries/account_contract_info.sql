SELECT
    COALESCE(MAX(current_contract_start_date), MAX(contract_start_date)) AS "Contract Start",
    MAX(current_contract_end_date) AS "Contract End",
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
    END AS "Elapsed",
    COALESCE(MAX(partner), 'N/A') AS "Channel"
FROM companies
WHERE name = '${company_name}'
    AND account_id IS NOT NULL
GROUP BY name
ORDER BY name ASC;
