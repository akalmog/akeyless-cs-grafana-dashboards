-- Bad Practice Risk: secret types and auth method hygiene from latest objects report.
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
        SUM(CASE WHEN ro.object_type LIKE '%static_secret%' THEN ro.amount ELSE 0 END) AS static_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%dynamic_secret%' THEN ro.amount ELSE 0 END) AS dynamic_secrets,
        SUM(CASE WHEN ro.object_type LIKE '%rotated_secret%' THEN ro.amount ELSE 0 END) AS rotated_secrets,
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
RiskRows AS (
    SELECT
        oc.latest_report_date,
        'Secrets — Static vs Dynamic/Rotated' AS category,
        oc.static_secrets AS less_preferred_count,
        oc.dynamic_secrets + oc.rotated_secrets AS preferred_count,
        ROUND(
            100.0 * oc.static_secrets / NULLIF(oc.static_secrets + oc.dynamic_secrets + oc.rotated_secrets, 0),
            1
        ) AS less_preferred_pct,
        CASE
            WHEN oc.static_secrets + oc.dynamic_secrets + oc.rotated_secrets = 0 THEN 'No Secrets Found'
            WHEN oc.static_secrets >= (oc.dynamic_secrets + oc.rotated_secrets) * 3
              OR oc.static_secrets > (oc.static_secrets + oc.dynamic_secrets + oc.rotated_secrets) * 0.8
                THEN 'Bad Practice — High Static Secret Ratio'
            ELSE 'Acceptable Secret Mix'
        END AS risk_status
    FROM ObjectCounts oc

    UNION ALL

    SELECT
        oc.latest_report_date,
        'Authentication — API Key vs Universal Identity' AS category,
        oc.auth_api_key AS less_preferred_count,
        oc.auth_universal_identity AS preferred_count,
        ROUND(
            100.0 * oc.auth_api_key / NULLIF(oc.auth_api_key + oc.auth_universal_identity, 0),
            1
        ) AS less_preferred_pct,
        CASE
            WHEN oc.auth_api_key + oc.auth_universal_identity = 0 THEN 'No API Key or Universal Identity Found'
            WHEN oc.auth_api_key > oc.auth_universal_identity
                THEN 'Bad Practice — API Key Count Exceeds Universal Identity'
            WHEN oc.auth_api_key > (oc.auth_api_key + oc.auth_universal_identity) * 0.5
                THEN 'Bad Practice — API Key Over 50% vs Universal Identity'
            ELSE 'Acceptable Universal Identity Mix'
        END AS risk_status
    FROM ObjectCounts oc

    UNION ALL

    SELECT
        oc.latest_report_date,
        'Authentication — API Key vs Cloud IAM (AWS IAM, GCP, Azure AD)' AS category,
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
                THEN 'Bad Practice — API Key Count Exceeds Cloud IAM'
            WHEN oc.auth_api_key > (
                oc.auth_api_key + oc.auth_aws_iam + oc.auth_azure_ad + oc.auth_gcp
            ) * 0.5
                THEN 'Bad Practice — API Key Over 50% vs Cloud IAM'
            ELSE 'Acceptable Cloud IAM Mix'
        END AS risk_status
    FROM ObjectCounts oc
)
SELECT
    category AS "Category",
    latest_report_date AS "Report Date",
    less_preferred_count AS "Less Preferred Count",
    preferred_count AS "Preferred Count",
    less_preferred_pct AS "Less Preferred %",
    risk_status AS "Bad Practice Risk"
FROM RiskRows
ORDER BY category
