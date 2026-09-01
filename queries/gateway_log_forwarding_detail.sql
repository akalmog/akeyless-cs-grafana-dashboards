-- Log forwarders from report_objects (latest snapshot). Named forwarders appear as object_type suffixes.
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
),
ForwarderRows AS (
    SELECT
        CASE
            WHEN norm_type IN (
                'gatewaylogforwarding',
                'gatewaylogforward',
                'logforwarding',
                'logforward'
            )
                THEN 'Log Forwarding (ObjectsReport total)'
            ELSE TRIM(
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
            )
        END AS forwarder_name,
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
    WHERE amount > 0
),
combined AS (
    SELECT forwarder_name, forwarder_type, 1 AS sort_order
    FROM ForwarderRows

    UNION ALL

    SELECT
        'No log forwarders in latest ObjectsReport' AS forwarder_name,
        '—' AS forwarder_type,
        2 AS sort_order
    WHERE NOT EXISTS (SELECT 1 FROM ForwarderRows)
)
SELECT
    forwarder_name AS "Name",
    forwarder_type AS "Type"
FROM combined
ORDER BY sort_order, forwarder_type, forwarder_name
