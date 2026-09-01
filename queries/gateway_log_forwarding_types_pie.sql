-- Log forwarding type mix from report_objects object_type suffixes (latest snapshot).
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
    WHERE {gateway_log_forward_match}
    GROUP BY ca.account_id
),
GatewayObjects AS (
    SELECT
        ro.object_type,
        ro.amount,
        {gateway_object_type_norm} AS norm_type
    FROM LatestGatewayReport lgr
    INNER JOIN report_objects ro
        ON ro.account_id = lgr.account_id
        AND ro.report_date = lgr.latest_report_date
    WHERE {gateway_log_forward_match}
      AND ro.amount > 0
),
ForwarderTypes AS (
    SELECT
        CASE
            WHEN norm_type IN (
                'gatewaylogforwarding',
                'gatewaylogforward',
                'logforwarding',
                'logforward'
            )
                THEN 'Aggregate'
            ELSE COALESCE(
                NULLIF(
                    TRIM(
                        REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(norm_type, 'gatewaylogforwarding', ''),
                                    'gatewaylogforward', ''
                                ),
                                'logforwarding', ''
                            ),
                            'logforward', ''
                        )
                    ),
                    ''
                ),
                'Configured'
            )
        END AS forwarder_type,
        amount
    FROM GatewayObjects
)
SELECT
    forwarder_type AS "Type",
    SUM(amount) AS "Count"
FROM ForwarderTypes
GROUP BY forwarder_type
ORDER BY SUM(amount) DESC, forwarder_type
