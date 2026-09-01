-- Gateway infrastructure month over month from report_objects (latest report per month).
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
MonthlyDates AS (
    SELECT DISTINCT
        ca.account_id,
        strftime('%Y-%m', ro.report_date) AS report_month,
        MAX(ro.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_objects ro ON ro.account_id = ca.account_id
    WHERE date(ro.report_date) >= {period_date_cutoff}
    GROUP BY ca.account_id, strftime('%Y-%m', ro.report_date)
),
MonthlyGateway AS (
    SELECT
        md.report_month,
        SUM(CASE WHEN {gateway_cluster_match} THEN ro.amount ELSE 0 END) AS gateway_clusters,
        SUM(CASE WHEN {gateway_instance_match} THEN ro.amount ELSE 0 END) AS gateway_instances,
        SUM(CASE WHEN {gateway_log_forward_match} THEN ro.amount ELSE 0 END) AS log_forwarding,
        SUM(CASE WHEN {gateway_any_match} THEN ro.amount ELSE 0 END) AS all_gateway_objects
    FROM MonthlyDates md
    INNER JOIN report_objects ro
        ON ro.account_id = md.account_id
        AND ro.report_date = md.latest_report_date
    GROUP BY md.report_month
),
WithPrevious AS (
    SELECT
        mg.*,
        LAG(gateway_clusters) OVER (ORDER BY mg.report_month) AS prev_clusters,
        LAG(gateway_instances) OVER (ORDER BY mg.report_month) AS prev_instances,
        LAG(log_forwarding) OVER (ORDER BY mg.report_month) AS prev_log_forwarding,
        LAG(all_gateway_objects) OVER (ORDER BY mg.report_month) AS prev_all_gateway
    FROM MonthlyGateway mg
),
TrendRows AS (
    SELECT
        wp.report_month AS month,
        COALESCE(wp.prev_clusters, 0) AS prev_clusters,
        wp.gateway_clusters,
        wp.gateway_clusters - COALESCE(wp.prev_clusters, 0) AS cluster_change,
        COALESCE(wp.prev_instances, 0) AS prev_instances,
        wp.gateway_instances,
        wp.gateway_instances - COALESCE(wp.prev_instances, 0) AS instance_change,
        wp.log_forwarding,
        wp.all_gateway_objects,
        CASE
            WHEN wp.prev_clusters IS NULL THEN 'First Month in Range'
            WHEN wp.all_gateway_objects = 0 THEN 'No Gateway Objects Reported'
            WHEN wp.gateway_clusters > COALESCE(wp.prev_clusters, 0)
              OR wp.gateway_instances > COALESCE(wp.prev_instances, 0) THEN 'Growth — Review Capacity'
            WHEN wp.gateway_clusters < COALESCE(wp.prev_clusters, 0)
              OR wp.gateway_instances < COALESCE(wp.prev_instances, 0) THEN 'Reduction — Review Change'
            ELSE 'Stable'
        END AS trend_alert,
        1 AS sort_order
    FROM WithPrevious wp
),
combined AS (
    SELECT
        month,
        prev_clusters,
        gateway_clusters,
        cluster_change,
        prev_instances,
        gateway_instances,
        instance_change,
        log_forwarding,
        all_gateway_objects,
        trend_alert,
        sort_order
    FROM TrendRows

    UNION ALL

    SELECT
        'Summary' AS month,
        NULL AS prev_clusters,
        NULL AS gateway_clusters,
        NULL AS cluster_change,
        NULL AS prev_instances,
        NULL AS gateway_instances,
        NULL AS instance_change,
        NULL AS log_forwarding,
        0 AS all_gateway_objects,
        'No gateway object types in reporting data for this account' AS trend_alert,
        0 AS sort_order
    WHERE NOT EXISTS (
        SELECT 1 FROM TrendRows WHERE all_gateway_objects > 0
    )
)
SELECT
    month AS "Month",
    prev_clusters AS "Previous Clusters",
    gateway_clusters AS "Gateway Clusters",
    cluster_change AS "Cluster Change",
    prev_instances AS "Previous Instances",
    gateway_instances AS "Gateway Instances",
    instance_change AS "Instance Change",
    log_forwarding AS "Log Forwarding",
    all_gateway_objects AS "All Gateway Objects",
    trend_alert AS "Trend Alert"
FROM combined
ORDER BY sort_order, month DESC
