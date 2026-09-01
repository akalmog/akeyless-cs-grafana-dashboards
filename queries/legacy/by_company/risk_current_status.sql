-- Latest client usage vs purchased limit — one row per customer + product.
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
LatestReportDate AS (
    SELECT
        ca.account_id,
        ca.company_name,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rc.report_date >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY ca.account_id, ca.company_name, rcp.product
),
ProductUsage AS (
    SELECT
        lrd.company_name,
        lrd.product,
        MAX(lrd.latest_report_date) AS report_date,
        SUM(rcp.amount) AS used_clients,
        SUM(rcp.exceeded_amount) AS exceeded_clients,
        SUM(CASE lrd.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
        END) AS purchased
    FROM LatestReportDate lrd
    INNER JOIN report_clients rc
        ON rc.account_id = lrd.account_id
        AND rc.report_date = lrd.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = lrd.product
    INNER JOIN companies c ON c.account_id = lrd.account_id
    GROUP BY lrd.company_name, lrd.product
)
SELECT
    pu.company_name AS "Customer",
    (SELECT GROUP_CONCAT(DISTINCT account_id)
     FROM CompanyAccounts ca_ids
     WHERE ca_ids.company_name = pu.company_name) AS "Account IDs",
    CASE pu.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
    END AS "Product",
    pu.report_date AS "Latest Report Date",
    pu.purchased AS "Purchased",
    pu.used_clients AS "Used",
    pu.exceeded_clients AS "Exceeded",
    CASE
        WHEN pu.purchased IN (0, 999, 99999) THEN NULL
        ELSE ROUND(100.0 * pu.used_clients / pu.purchased, 1)
    END AS "Usage %",
    CASE
        WHEN pu.exceeded_clients > 0 THEN 'Exceeded Clients Detected'
        WHEN pu.purchased NOT IN (0, 999, 99999)
          AND pu.used_clients > pu.purchased THEN 'Over Purchased Limit'
        WHEN pu.purchased NOT IN (0, 999, 99999)
          AND pu.used_clients >= pu.purchased * 0.9 THEN 'Near Limit (90%+)'
        WHEN pu.purchased NOT IN (0, 999, 99999)
          AND pu.used_clients < pu.purchased * 0.3 THEN 'Under-Adopted (<30%)'
        ELSE 'Within Normal Range'
    END AS "Risk Status"
FROM ProductUsage pu
ORDER BY pu.company_name, pu.product
