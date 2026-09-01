-- Usage change across the last 3 completed calendar months (includes usage-drop detection).
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
Products AS (
    SELECT 'sm' AS product
    UNION ALL SELECT 'sra'
    UNION ALL SELECT 'apm'
),
LastFullMonth AS (
    SELECT strftime('%Y-%m', 'now', 'start of month', '-1 month') AS report_month
),
WindowStartMonth AS (
    SELECT strftime('%Y-%m', date((SELECT report_month FROM LastFullMonth) || '-01', '-2 month')) AS report_month
),
WindowBounds AS (
    SELECT
        (SELECT report_month FROM WindowStartMonth) AS start_month,
        (SELECT report_month FROM LastFullMonth) AS end_month
),
CalendarMonths AS (
    SELECT (SELECT report_month FROM WindowStartMonth) AS report_month
    UNION ALL
    SELECT strftime('%Y-%m', date((SELECT report_month FROM LastFullMonth) || '-01', '-1 month'))
    UNION ALL
    SELECT (SELECT report_month FROM LastFullMonth) AS report_month
),
MonthlyLatestReport AS (
    SELECT
        ca.account_id,
        strftime('%Y-%m', rc.report_date) AS report_month,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND strftime('%Y-%m', rc.report_date) IN (SELECT report_month FROM CalendarMonths)
    GROUP BY ca.account_id, strftime('%Y-%m', rc.report_date), rcp.product
),
MonthlyProductUsage AS (
    SELECT
        mlr.account_id,
        mlr.report_month,
        mlr.product,
        SUM(rcp.amount) AS used_in_limit,
        SUM(rcp.exceeded_amount) AS exceeded_clients,
        SUM(rcp.amount + rcp.exceeded_amount) AS total_clients
    FROM MonthlyLatestReport mlr
    INNER JOIN report_clients rc
        ON rc.account_id = mlr.account_id
        AND rc.report_date = mlr.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = mlr.product
    GROUP BY mlr.account_id, mlr.report_month, mlr.product
),
StartMonthUsage AS (
    SELECT mpu.account_id, mpu.product, mpu.used_in_limit, mpu.total_clients
    FROM MonthlyProductUsage mpu
    INNER JOIN WindowStartMonth wsm ON wsm.report_month = mpu.report_month
),
EndMonthUsage AS (
    SELECT mpu.account_id, mpu.product, mpu.used_in_limit, mpu.total_clients, mpu.exceeded_clients
    FROM MonthlyProductUsage mpu
    INNER JOIN LastFullMonth lfm ON lfm.report_month = mpu.report_month
)
SELECT
    c.name AS "Customer",
    c.account_id AS "Account ID",
    CASE p.product
        WHEN 'sm' THEN 'SM'
        WHEN 'sra' THEN 'SRA'
        WHEN 'apm' THEN 'PWM'
    END AS "Product",
    (SELECT start_month FROM WindowBounds) || ' → ' || (SELECT end_month FROM WindowBounds) AS "Period",
    CAST(COALESCE(start_u.used_in_limit, 0) AS TEXT) || ' → ' || CAST(COALESCE(end_u.used_in_limit, 0) AS TEXT) AS "Used",
    CAST(COALESCE(start_u.total_clients, 0) AS TEXT) || ' → ' || CAST(COALESCE(end_u.total_clients, 0) AS TEXT) AS "Total",
    COALESCE(end_u.total_clients, 0) - COALESCE(start_u.total_clients, 0) AS "Change",
    COALESCE(end_u.exceeded_clients, 0) AS "Last Exceeded",
    CASE
        WHEN start_u.total_clients IS NULL AND COALESCE(end_u.total_clients, 0) = 0 THEN 'No Client Reports in Range'
        WHEN start_u.total_clients IS NULL OR start_u.total_clients = 0 THEN
            CASE
                WHEN COALESCE(end_u.total_clients, 0) = 0 THEN 'Stable'
                ELSE 'First Month in Range'
            END
        WHEN COALESCE(end_u.total_clients, 0) < start_u.total_clients * 0.8 THEN 'Drop Over 20% — Review'
        WHEN COALESCE(end_u.total_clients, 0) > start_u.total_clients * 1.2 THEN 'Spike Over 20% — Review'
        WHEN COALESCE(end_u.exceeded_clients, 0) > 0 THEN 'Exceeded Clients — Review'
        ELSE 'Stable'
    END AS "Alert"
FROM CompanyAccounts ca
CROSS JOIN Products p
INNER JOIN companies c ON c.account_id = ca.account_id
LEFT JOIN StartMonthUsage start_u ON start_u.account_id = ca.account_id AND start_u.product = p.product
LEFT JOIN EndMonthUsage end_u ON end_u.account_id = ca.account_id AND end_u.product = p.product
WHERE COALESCE(end_u.total_clients, 0) > 0
   OR COALESCE(start_u.total_clients, 0) > 0
   OR COALESCE(end_u.exceeded_clients, 0) > 0
ORDER BY c.name, p.product
