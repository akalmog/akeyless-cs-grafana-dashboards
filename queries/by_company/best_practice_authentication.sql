-- Best practice: one row per customer — static credentials vs secretless authentication.
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
        MAX(lor.latest_report_date) AS latest_report_date,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_api_key%' THEN ro.amount ELSE 0 END) AS static_credentials,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_universal_identity%' THEN ro.amount ELSE 0 END)
            + SUM(CASE WHEN ro.object_type LIKE '%auth_method_aws_iam%' THEN ro.amount ELSE 0 END)
            + SUM(CASE WHEN ro.object_type LIKE '%auth_method_azure_ad%' THEN ro.amount ELSE 0 END)
            + SUM(CASE WHEN ro.object_type LIKE '%auth_method_gcp%' THEN ro.amount ELSE 0 END)
            + SUM(CASE WHEN ro.object_type LIKE '%auth_method_jwt%' THEN ro.amount ELSE 0 END)
            + SUM(CASE WHEN ro.object_type LIKE '%auth_method_kubernetes%' THEN ro.amount ELSE 0 END)
            AS secretless_authentication
    FROM LatestObjectReport lor
    INNER JOIN CompanyAccounts ca ON ca.account_id = lor.account_id
    INNER JOIN report_objects ro
        ON ro.account_id = lor.account_id
        AND ro.report_date = lor.latest_report_date
    GROUP BY ca.company_name
)
SELECT
    oc.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = oc.company_name) AS "Account IDs",
    'Static vs Secretless Credentials' AS "Comparison",
    oc.latest_report_date AS "Report Date",
    oc.static_credentials AS "API Key Count",
    oc.secretless_authentication AS "Secretless Authentication",
    ROUND(
        100.0 * oc.static_credentials
            / NULLIF(oc.static_credentials + oc.secretless_authentication, 0),
        1
    ) AS "API Key %",
    CASE
        WHEN oc.static_credentials + oc.secretless_authentication = 0
            THEN 'No Static Credentials or Secretless Found'
        WHEN oc.static_credentials > oc.secretless_authentication
            OR oc.static_credentials > (oc.static_credentials + oc.secretless_authentication) * 0.5
            THEN 'Offer Transition for Secretless Authentication'
        ELSE 'Acceptable Secretless Mix'
    END AS "Recommendation"
FROM ObjectCounts oc
WHERE oc.static_credentials > 0 OR oc.secretless_authentication > 0
ORDER BY oc.company_name
