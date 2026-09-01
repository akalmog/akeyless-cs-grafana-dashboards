-- Best practice: authentication method comparisons from latest objects report (per customer).
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
        lor.account_id,
        lor.latest_report_date,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_api_key%' THEN ro.amount ELSE 0 END) AS auth_api_key,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_universal_identity%' THEN ro.amount ELSE 0 END) AS auth_universal_identity,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_aws_iam%' THEN ro.amount ELSE 0 END) AS auth_aws_iam,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_azure_ad%' THEN ro.amount ELSE 0 END) AS auth_azure_ad,
        SUM(CASE WHEN ro.object_type LIKE '%auth_method_gcp%' THEN ro.amount ELSE 0 END) AS auth_gcp
    FROM LatestObjectReport lor
    INNER JOIN report_objects ro
        ON ro.account_id = lor.account_id
        AND ro.report_date = lor.latest_report_date
    GROUP BY lor.account_id, lor.latest_report_date
),
AuthRows AS (
    SELECT
        oc.account_id,
        oc.latest_report_date,
        'Authentication — API Key vs Universal Identity' AS comparison,
        oc.auth_api_key AS less_preferred_count,
        oc.auth_universal_identity AS preferred_count,
        ROUND(
            100.0 * oc.auth_api_key / NULLIF(oc.auth_api_key + oc.auth_universal_identity, 0),
            1
        ) AS less_preferred_pct,
        CASE
            WHEN oc.auth_api_key + oc.auth_universal_identity = 0 THEN 'No API Key or Universal Identity Found'
            WHEN oc.auth_api_key > oc.auth_universal_identity
                THEN 'Recommend — Migrate to Universal Identity'
            WHEN oc.auth_api_key > (oc.auth_api_key + oc.auth_universal_identity) * 0.5
                THEN 'Recommend — Reduce API Key Share'
            ELSE 'Acceptable Universal Identity Mix'
        END AS recommendation
    FROM ObjectCounts oc

    UNION ALL

    SELECT
        oc.account_id,
        oc.latest_report_date,
        'Authentication — API Key vs Cloud IAM (AWS IAM, GCP, Azure AD)' AS comparison,
        oc.auth_api_key AS less_preferred_count,
        oc.auth_aws_iam + oc.auth_azure_ad + oc.auth_gcp AS preferred_count,
        ROUND(
            100.0 * oc.auth_api_key / NULLIF(
                oc.auth_api_key + oc.auth_aws_iam + oc.auth_azure_ad + oc.auth_gcp,
                0
            ),
            1
        ) AS less_preferred_pct,
        CASE
            WHEN oc.auth_api_key + oc.auth_aws_iam + oc.auth_azure_ad + oc.auth_gcp = 0
                THEN 'No API Key or Cloud IAM Found'
            WHEN oc.auth_api_key > oc.auth_aws_iam + oc.auth_azure_ad + oc.auth_gcp
                THEN 'Recommend — Migrate to Cloud IAM'
            WHEN oc.auth_api_key > (
                oc.auth_api_key + oc.auth_aws_iam + oc.auth_azure_ad + oc.auth_gcp
            ) * 0.5
                THEN 'Recommend — Reduce API Key Share'
            ELSE 'Acceptable Cloud IAM Mix'
        END AS recommendation
    FROM ObjectCounts oc
)
SELECT
    c.name AS "Customer",
    c.account_id AS "Account ID",
    ar.comparison AS "Comparison",
    ar.latest_report_date AS "Report Date",
    ar.less_preferred_count AS "API Key Count",
    ar.preferred_count AS "Preferred Method Count",
    ar.less_preferred_pct AS "API Key %",
    ar.recommendation AS "Recommendation"
FROM AuthRows ar
INNER JOIN companies c ON c.account_id = ar.account_id
ORDER BY c.name, ar.comparison
