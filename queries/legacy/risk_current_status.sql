-- Latest client usage vs purchased limit (same logic as SM/SRA/PM "Used" stat panels).
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
LatestReportDate AS (
    SELECT
        ca.account_id,
        rcp.product,
        MAX(rc.report_date) AS latest_report_date
    FROM CompanyAccounts ca
    INNER JOIN report_clients rc ON rc.account_id = ca.account_id
    INNER JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    WHERE rcp.product IN ('sm', 'sra', 'apm')
      AND rc.report_date >= date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))
    GROUP BY ca.account_id, rcp.product
),
ProductUsage AS (
    SELECT
        lrd.account_id,
        lrd.product,
        lrd.latest_report_date AS report_date,
        SUM(rcp.amount) AS used_clients,
        SUM(rcp.exceeded_amount) AS exceeded_clients
    FROM LatestReportDate lrd
    INNER JOIN report_clients rc
        ON rc.account_id = lrd.account_id
        AND rc.report_date = lrd.latest_report_date
    INNER JOIN report_clients_product_info rcp
        ON rcp.report_client_id = rc.id
        AND rcp.product = lrd.product
    GROUP BY lrd.account_id, lrd.product, lrd.latest_report_date
)
SELECT
    c.name AS "Customer",
    c.account_id AS "Account ID",
    CASE pu.product
        WHEN 'sm' THEN 'SM — Secrets Management'
        WHEN 'sra' THEN 'SRA — Secure Remote Access'
        WHEN 'apm' THEN 'PM — Password Management'
    END AS "Product",
    pu.report_date AS "Latest Report Date",
    CASE pu.product
        WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
        WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
        WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
    END AS "Purchased",
    pu.used_clients AS "Used",
    pu.exceeded_clients AS "Exceeded",
    CASE
        WHEN CASE pu.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
        END IN (0, 999, 99999) THEN NULL
        ELSE ROUND(
            100.0 * pu.used_clients / CASE pu.product
                WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
                WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
                WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
            END,
            1
        )
    END AS "Usage %",
    CASE
        WHEN pu.exceeded_clients > 0 THEN 'Exceeded Clients Detected'
        WHEN CASE pu.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
        END NOT IN (0, 999, 99999)
          AND pu.used_clients > CASE pu.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
          END THEN 'Over Purchased Limit'
        WHEN CASE pu.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
        END NOT IN (0, 999, 99999)
          AND pu.used_clients >= CASE pu.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
          END * 0.9 THEN 'Near Limit (90%+)'
        WHEN CASE pu.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
        END NOT IN (0, 999, 99999)
          AND pu.used_clients < CASE pu.product
            WHEN 'sm' THEN CAST(c.clients_sm AS INTEGER)
            WHEN 'sra' THEN CAST(c.clients_sra AS INTEGER)
            WHEN 'apm' THEN CAST(c.clients_pm AS INTEGER)
          END * 0.3 THEN 'Under-Adopted (<30%)'
        ELSE 'Within Normal Range'
    END AS "Risk Status"
FROM ProductUsage pu
INNER JOIN companies c ON c.account_id = pu.account_id
ORDER BY c.name, pu.product
