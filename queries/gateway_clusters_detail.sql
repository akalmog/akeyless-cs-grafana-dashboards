-- Gateway inventory from report_objects (latest snapshot). Per-cluster access-id requires BIS detail ingest.
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
LatestGatewayReport AS (
    SELECT
        ca.account_id,
        MAX(ro.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_objects ro ON ro.account_id = ca.account_id
    WHERE {gateway_any_match}
    GROUP BY ca.account_id
),
GatewayObjects AS (
    SELECT
        lgr.account_id,
        lgr.latest_report_date,
        ro.object_type,
        ro.amount,
        {gateway_object_type_norm} AS norm_type
    FROM LatestGatewayReport lgr
    INNER JOIN report_objects ro
        ON ro.account_id = lgr.account_id
        AND ro.report_date = lgr.latest_report_date
    WHERE {gateway_any_match}
),
Totals AS (
    SELECT
        SUM(CASE WHEN {gateway_cluster_match} THEN amount ELSE 0 END) AS cluster_count,
        SUM(CASE WHEN {gateway_instance_match} THEN amount ELSE 0 END) AS instance_count
    FROM GatewayObjects
),
NamedClusters AS (
    SELECT
        TRIM(
            REPLACE(
                REPLACE(
                    REPLACE(
                        REPLACE(
                            REPLACE(norm_type, 'gatewaycluster', ''),
                            'gatorcluster', ''
                        ),
                        'gwcluster', ''
                    ),
                    '/',
                    ' '
                ),
                'cluster',
                ' '
            )
        ) AS parsed_name,
        amount
    FROM GatewayObjects
    WHERE {gateway_cluster_match}
      AND norm_type NOT IN ('gatewaycluster', 'gatorcluster', 'gwcluster', 'gatewayclusters')
      AND amount > 0
),
UnmatchedGatewayRows AS (
    SELECT object_type, amount
    FROM GatewayObjects
    WHERE amount > 0
      AND NOT ({gateway_cluster_match})
      AND NOT ({gateway_instance_match})
      AND NOT ({gateway_log_forward_match})
),
ClusterRows AS (
    SELECT
        CASE
            WHEN parsed_name IS NOT NULL AND parsed_name != '' THEN parsed_name
            ELSE 'Unnamed Cluster'
        END AS cluster_name,
        amount AS instance_count,
        '—' AS access_id,
        'Active' AS status,
        1 AS sort_order
    FROM NamedClusters
    WHERE parsed_name IS NOT NULL AND parsed_name != ''

    UNION ALL

    SELECT
        object_type AS cluster_name,
        amount AS instance_count,
        'Raw object_type' AS access_id,
        'Unmatched type' AS status,
        1 AS sort_order
    FROM UnmatchedGatewayRows

    UNION ALL

    SELECT
        'Gateway Clusters (ObjectsReport total)' AS cluster_name,
        t.cluster_count AS instance_count,
        'Not in ObjectsReport' AS access_id,
        CASE WHEN t.cluster_count > 0 THEN 'Active' ELSE 'No Data' END AS status,
        2 AS sort_order
    FROM Totals t
    WHERE NOT EXISTS (SELECT 1 FROM NamedClusters WHERE parsed_name IS NOT NULL AND parsed_name != '')
      AND NOT EXISTS (SELECT 1 FROM UnmatchedGatewayRows)
      AND t.cluster_count > 0

    UNION ALL

    SELECT
        'Gateway Instances (ObjectsReport total)' AS cluster_name,
        t.instance_count AS instance_count,
        'Not in ObjectsReport' AS access_id,
        CASE WHEN t.instance_count > 0 THEN 'Active' ELSE 'No Data' END AS status,
        3 AS sort_order
    FROM Totals t
    WHERE NOT EXISTS (SELECT 1 FROM NamedClusters WHERE parsed_name IS NOT NULL AND parsed_name != '')
      AND NOT EXISTS (SELECT 1 FROM UnmatchedGatewayRows)
      AND t.instance_count > 0

    UNION ALL

    SELECT
        'No gateway clusters in latest ObjectsReport' AS cluster_name,
        NULL AS instance_count,
        '—' AS access_id,
        'No Data' AS status,
        4 AS sort_order
    FROM Totals t
    WHERE t.cluster_count = 0
      AND t.instance_count = 0
      AND NOT EXISTS (SELECT 1 FROM NamedClusters WHERE parsed_name IS NOT NULL AND parsed_name != '')
      AND NOT EXISTS (SELECT 1 FROM UnmatchedGatewayRows)
)
SELECT
    cluster_name AS "Cluster",
    instance_count AS "Instances",
    access_id AS "Access ID",
    status AS "Status"
FROM ClusterRows
ORDER BY sort_order, instance_count DESC, cluster_name
