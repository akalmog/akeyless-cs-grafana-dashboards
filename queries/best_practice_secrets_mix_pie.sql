-- Pie chart: secret type breakdown from latest objects report (non-zero only).
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
),
LatestObjectReport AS (
    SELECT ro.account_id, MAX(ro.report_date) AS latest_report_date
    FROM report_objects ro
    INNER JOIN CompanyAccounts ca ON ca.account_id = ro.account_id
    GROUP BY ro.account_id
),
ObjectCounts AS (
    SELECT
        SUM(CASE WHEN ro.object_type LIKE '%static_secret%' THEN ro.amount ELSE 0 END) AS static_secrets,
        SUM(CASE WHEN (
              ro.object_type LIKE '%password%'
              OR ro.object_type LIKE '%managed_password%'
              OR ro.object_type LIKE '%personal_password%'
              OR ro.object_type LIKE '%shared_password%'
            )
            AND ro.object_type NOT LIKE '%static_secret%'
            AND ro.object_type NOT LIKE '%dynamic_secret%'
            AND ro.object_type NOT LIKE '%rotated_secret%' THEN ro.amount ELSE 0 END) AS passwords,
        SUM(CASE WHEN ro.object_type LIKE '%dynamic_secret%' THEN ro.amount ELSE 0 END) AS dynamic_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%rotated_secret%' THEN ro.amount ELSE 0 END) AS rotated_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%certificate%'
              OR ro.object_type LIKE '%pki_cert_issuer%'
              OR ro.object_type LIKE '%ssh_cert_issuer%' THEN ro.amount ELSE 0 END) AS certificates
    FROM LatestObjectReport lor
    INNER JOIN report_objects ro
        ON ro.account_id = lor.account_id
        AND ro.report_date = lor.latest_report_date
)
SELECT 'Static' AS "Secret Type", static_secrets AS "Count"
FROM ObjectCounts
WHERE static_secrets > 0
UNION ALL
SELECT 'Password', passwords FROM ObjectCounts WHERE passwords > 0
UNION ALL
SELECT 'Dynamic', dynamic_secrets FROM ObjectCounts WHERE dynamic_secrets > 0
UNION ALL
SELECT 'Rotated', rotated_secrets FROM ObjectCounts WHERE rotated_secrets > 0
UNION ALL
SELECT 'Certificate', certificates FROM ObjectCounts WHERE certificates > 0
ORDER BY "Count" DESC
