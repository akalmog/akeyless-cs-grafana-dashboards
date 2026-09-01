-- Headline stat: highest API key share across auth comparisons.
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
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_api_key%' THEN ro.amount ELSE 0 END) AS auth_api_key,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_universal_identity%' THEN ro.amount ELSE 0 END) AS auth_universal_identity,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_aws_iam%' THEN ro.amount ELSE 0 END) AS auth_aws_iam,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_azure_ad%' THEN ro.amount ELSE 0 END) AS auth_azure_ad,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_gcp%' THEN ro.amount ELSE 0 END) AS auth_gcp
    FROM LatestObjectReport lor
    INNER JOIN report_objects ro
        ON ro.account_id = lor.account_id
        AND ro.report_date = lor.latest_report_date
),
Shares AS (
    SELECT ROUND(
        100.0 * auth_api_key / NULLIF(auth_api_key + auth_universal_identity, 0),
        1
    ) AS ui_share
    FROM ObjectCounts
    UNION ALL
    SELECT ROUND(
        100.0 * auth_api_key / NULLIF(
            auth_api_key + auth_aws_iam + auth_azure_ad + auth_gcp,
            0
        ),
        1
    )
    FROM ObjectCounts
)
SELECT MAX(ui_share) AS value FROM Shares
