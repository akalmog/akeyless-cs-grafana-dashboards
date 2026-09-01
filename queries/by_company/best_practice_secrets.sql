-- Best practice: secret type mix aggregated by customer name.
WITH CompanyAccounts AS (
    SELECT DISTINCT account_id, name AS company_name
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
        ca.company_name,
        lor.latest_report_date,
        SUM(CASE WHEN ro.object_type LIKE '%static_secret%' THEN ro.amount ELSE 0 END) AS static_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%dynamic_secret%' THEN ro.amount ELSE 0 END) AS dynamic_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%rotated_secret%' THEN ro.amount ELSE 0 END) AS rotated_secrets
    FROM LatestObjectReport lor
    INNER JOIN CompanyAccounts ca ON ca.account_id = lor.account_id
    INNER JOIN report_objects ro
        ON ro.account_id = lor.account_id
        AND ro.report_date = lor.latest_report_date
    GROUP BY ca.company_name, lor.latest_report_date
)
SELECT
    oc.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = oc.company_name) AS "Account IDs",
    'Static vs Dynamic/Rotated' AS "Comparison",
    MAX(oc.latest_report_date) AS "Report Date",
    SUM(oc.static_secrets) AS "Static Secrets",
    SUM(oc.dynamic_secrets) + SUM(oc.rotated_secrets) AS "Dynamic + Rotated Secrets",
    ROUND(
        100.0 * SUM(oc.static_secrets) / NULLIF(
            SUM(oc.static_secrets) + SUM(oc.dynamic_secrets) + SUM(oc.rotated_secrets),
            0
        ),
        1
    ) AS "Static %",
    CASE
        WHEN SUM(oc.static_secrets) + SUM(oc.dynamic_secrets) + SUM(oc.rotated_secrets) = 0 THEN 'No Secrets Found'
        WHEN SUM(oc.static_secrets) >= (SUM(oc.dynamic_secrets) + SUM(oc.rotated_secrets)) * 3
          OR SUM(oc.static_secrets) > (
            SUM(oc.static_secrets) + SUM(oc.dynamic_secrets) + SUM(oc.rotated_secrets)
          ) * 0.8
            THEN 'Recommend — Increase Dynamic/Rotated Secrets'
        ELSE 'Acceptable Secret Mix'
    END AS "Recommendation"
FROM ObjectCounts oc
GROUP BY oc.company_name
ORDER BY oc.company_name
