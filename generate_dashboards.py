#!/usr/bin/env python3
"""Generate Akeyless CS Grafana dashboard JSON.

Outputs:
  dashboard-single-account.json       — production single-account dashboard
  dashboard-multi-account.json        — production multi-account dashboard
  dashboard-portfolio-anomalies.json  — production portfolio anomalies dashboard
  test-single-account.json            — test copy of single-account dashboard
  test-multiple-accounts.json         — test copy of multi-account dashboard
"""

import json
from datetime import date
from copy import deepcopy
from pathlib import Path

OUT_DIR = Path(__file__).parent
QUERIES_DIR = OUT_DIR / "queries"
# uid=None uses the org default datasource ("Active Customers Data" on akeyless-analytics.com)
DS = {"type": "frser-sqlite-datasource", "uid": None}

REPORT_JOIN = "JOIN reports r ON r.id = rc.report_id AND r.report_type = 'clients_report'"
PRODUCTS = [
    ("SM", "sm", "clients_sm"),
    ("CLM", "ca", "clients_ca"),
    ("SRA", "sra", "clients_sra"),
    ("PWM", "apm", "clients_pm"),
]

# Grafana multi-select "All" must use a quoted allValue (% → IN ('%')) — bare All breaks IN (All).
VAR_ALL_VALUE = "%"
COMPANY_ALL_CHECK = "'${company_name:raw}' IN ('All', '%', '$__all')"
ACCOUNT_ALL_CHECK = "'${account_id:raw}' IN ('All', '%', '$__all')"


def account_match_expr(column: str) -> str:
    return f"({ACCOUNT_ALL_CHECK} OR {column} IN (${{account_id:sqlstring}}))"


def company_match_expr(column: str) -> str:
    return f"({COMPANY_ALL_CHECK} OR {column} IN (${{company_name:sqlstring}}))"


PERIOD_3 = "3 Months"
PERIOD_12 = "12 Months"
PERIOD_OPTIONS = [
    {"selected": True, "text": "12 Months", "value": "12 Months"},
    {"selected": False, "text": "3 Months", "value": "3 Months"},
]
PERIOD_CURRENT = {"selected": True, "text": "12 Months", "value": "12 Months"}
PERIOD_DATE_CUTOFF = (
    "date('now', printf('-%d months', CASE WHEN '${period_months}' LIKE '3%' THEN 3 ELSE 12 END))"
)

TIME_RANGE_3 = "Last 3 Months"
TIME_RANGE_6 = "Last 6 Months"
TIME_RANGE_12 = "Last 12 Months"
TIME_RANGE_CONTRACT = "From Contract Start"
TIME_RANGE_CONTRACT_12 = "From Contract Start Last 12 Months"
TIME_RANGE_OPTIONS = [
    {"selected": False, "text": TIME_RANGE_3, "value": TIME_RANGE_3},
    {"selected": False, "text": TIME_RANGE_6, "value": TIME_RANGE_6},
    {"selected": True, "text": TIME_RANGE_12, "value": TIME_RANGE_12},
    {"selected": False, "text": TIME_RANGE_CONTRACT, "value": TIME_RANGE_CONTRACT},
    {"selected": False, "text": TIME_RANGE_CONTRACT_12, "value": TIME_RANGE_CONTRACT_12},
]
TIME_RANGE_CURRENT = {"selected": True, "text": TIME_RANGE_12, "value": TIME_RANGE_12}
TIME_RANGE_QUERY = (
    f"{TIME_RANGE_3},{TIME_RANGE_6},{TIME_RANGE_12},"
    f"{TIME_RANGE_CONTRACT},{TIME_RANGE_CONTRACT_12}"
)

COMPANY_SCOPE_FILTER = """(
    '${company_name:raw}' IN ('All', '%', '$__all')
    OR name IN (${company_name:sqlstring})
    OR name = '${company_name}'
)"""


def company_scope_contract_start_min_sql():
    return f"""(SELECT MIN(substr(c.current_contract_start_date, 1, 10))
        FROM companies c
        WHERE c.current_contract_start_date IS NOT NULL AND c.current_contract_start_date != ''
          AND c.account_id IS NOT NULL AND c.account_id != ''
          AND {COMPANY_SCOPE_FILTER})"""


def time_range_months_back_case():
    return """CASE
        WHEN '${period_months}' = 'Current Month' THEN 1
        WHEN '${period_months}' = 'Last 3 Months' OR '${period_months}' LIKE '3 Months' THEN 3
        WHEN '${period_months}' = 'Last 6 Months' THEN 6
        WHEN '${period_months}' = 'Last 9 Months' THEN 9
        WHEN '${period_months}' = 'Last 12 Months' OR '${period_months}' LIKE '12 Months' THEN 12
        WHEN '${period_months}' = 'Last 24 Months' THEN 24
        WHEN '${period_months}' = 'From Contract Start' THEN CAST((
            julianday('now') - julianday(COALESCE(""" + company_scope_contract_start_min_sql() + """, strftime('%Y-%m-%d', 'now', '-12 months')))
        ) / 30.44 AS INTEGER)
        WHEN '${period_months}' = 'From Contract Start Last 12 Months' THEN 12
        ELSE 12
    END"""


def time_range_start_sql(contract_date_expr=None):
    contract_ref = contract_date_expr or company_scope_contract_start_min_sql()
    return f"""CASE
        WHEN '${{period_months}}' = 'Current Month' THEN strftime('%Y-%m-%d', 'now', 'start of month')
        WHEN '${{period_months}}' = 'Last 3 Months' OR '${{period_months}}' LIKE '3 Months' THEN strftime('%Y-%m-%d', 'now', '-3 months')
        WHEN '${{period_months}}' = 'Last 6 Months' THEN strftime('%Y-%m-%d', 'now', '-6 months')
        WHEN '${{period_months}}' = 'Last 9 Months' THEN strftime('%Y-%m-%d', 'now', '-9 months')
        WHEN '${{period_months}}' = 'Last 12 Months' OR '${{period_months}}' LIKE '12 Months' THEN strftime('%Y-%m-%d', 'now', '-12 months')
        WHEN '${{period_months}}' = 'Last 24 Months' THEN strftime('%Y-%m-%d', 'now', '-24 months')
        WHEN '${{period_months}}' = 'From Contract Start' THEN
            COALESCE({contract_ref}, strftime('%Y-%m-%d', 'now', '-12 months'))
        WHEN '${{period_months}}' = 'From Contract Start Last 12 Months' THEN
            CASE WHEN {contract_ref} IS NOT NULL AND {contract_ref} != '' THEN
                CASE WHEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_ref}, 1, 10))) > date('now')
                    THEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_ref}, 1, 10)), '-1 year')
                    ELSE date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_ref}, 1, 10)))
                END
            ELSE strftime('%Y-%m-%d', 'now', 'start of month', '-11 months')
            END
        ELSE strftime('%Y-%m-%d', 'now', '-12 months')
    END"""


def time_range_end_sql(contract_date_expr=None):
    contract_ref = contract_date_expr or company_scope_contract_start_min_sql()
    return f"""CASE
        WHEN '${{period_months}}' = 'From Contract Start Last 12 Months' THEN
            CASE WHEN {contract_ref} IS NOT NULL AND {contract_ref} != '' THEN
                CASE WHEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_ref}, 1, 10))) > date('now')
                    THEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_ref}, 1, 10)))
                    ELSE date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_ref}, 1, 10)), '+1 year')
                END
            ELSE strftime('%Y-%m-%d', 'now')
            END
        ELSE strftime('%Y-%m-%d', 'now')
    END"""


def time_range_date_cutoff_sql():
    contract_min = company_scope_contract_start_min_sql()
    return f"""date(
        CASE
            WHEN '${{period_months}}' = 'From Contract Start' THEN
                COALESCE({contract_min}, strftime('%Y-%m-%d', 'now', '-12 months'))
            WHEN '${{period_months}}' = 'From Contract Start Last 12 Months' THEN
                COALESCE(
                    CASE WHEN {contract_min} IS NOT NULL AND {contract_min} != '' THEN
                        CASE WHEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_min}, 1, 10))) > date('now')
                            THEN date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_min}, 1, 10)), '-1 year')
                            ELSE date(strftime('%Y', 'now') || '-' || strftime('%m-%d', substr({contract_min}, 1, 10)))
                        END
                    ELSE strftime('%Y-%m-%d', 'now', 'start of month', '-11 months')
                    END,
                    strftime('%Y-%m-%d', 'now', 'start of month', '-11 months'))
            WHEN '${{period_months}}' = 'Current Month' THEN strftime('%Y-%m-%d', 'now', 'start of month')
            ELSE strftime('%Y-%m-%d', 'now', printf('-%d months', {time_range_months_back_case()}))
        END
    )"""


def time_range_sql_replacements(contract_date_expr="ahsd.current_contract_start_date"):
    if not contract_date_expr:
        contract_date_expr = None
    contract_ref = contract_date_expr or company_scope_contract_start_min_sql()
    return {
        "time_range_start": time_range_start_sql(contract_ref),
        "time_range_end": time_range_end_sql(contract_ref),
        "time_range_month_count": time_range_months_back_case(),
        "period_date_cutoff": time_range_date_cutoff_sql(),
    }


def period_variable(experimental=True):
    if experimental:
        return {
            "name": "period_months",
            "type": "custom",
            "label": "Time Range",
            "query": TIME_RANGE_QUERY,
            "options": TIME_RANGE_OPTIONS,
            "current": TIME_RANGE_CURRENT,
            "includeAll": False,
            "multi": False,
        }
    return {
        "name": "period_months",
        "type": "custom",
        "label": "Period",
        "query": f"{PERIOD_12},{PERIOD_3}",
        "options": PERIOD_OPTIONS,
        "current": PERIOD_CURRENT,
        "includeAll": False,
        "multi": False,
    }


TIME_RANGE_DATE_CUTOFF = time_range_date_cutoff_sql()

UTIL_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "red", "value": None},
        {"color": "#5794F2", "value": 30},
        {"color": "green", "value": 70},
    ],
}

# Original "By Customer" product usage gauge (SM - Usage, etc.)
ORIGINAL_PRODUCT_USAGE_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "red", "value": None},
        {"color": "orange", "value": 20},
        {"color": "green", "value": 60},
    ],
}

SM_UTIL_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "super-light-red", "value": None},
        {"color": "super-light-blue", "value": 30},
        {"color": "super-light-green", "value": 70},
    ],
}

INVERSE_PCT_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "green", "value": None},
        {"color": "yellow", "value": 50},
        {"color": "orange", "value": 70},
        {"color": "red", "value": 85},
    ],
}

POSITIVE_COUNT_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "red", "value": None},
        {"color": "yellow", "value": 1},
        {"color": "green", "value": 10},
    ],
}

CHANGE_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "red", "value": None},
        {"color": "yellow", "value": -5},
        {"color": "green", "value": 0},
        {"color": "orange", "value": 10},
        {"color": "red", "value": 25},
    ],
}

GROWTH_POSITIVE_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "orange", "value": None},
        {"color": "blue", "value": 31},
        {"color": "green", "value": 71},
    ],
}

OBJECT_TREND_CHANGE_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "red", "value": None},
        {"color": "orange", "value": 0},
        {"color": "blue", "value": 31},
        {"color": "green", "value": 71},
    ],
}

RISK_STATUS_COLORS = [
    ("Under-Adopted — Contract Active 90+ Days", "red"),
    ("Under-Adopted (<30%)", "red"),
    ("Exceeded Clients Detected", "red"),
    ("Over Purchased Limit", "red"),
    ("Near Limit (90%+)", "orange"),
    ("Early Contract — Monitor", "blue"),
    ("On Track", "green"),
    ("Within Normal Range", "green"),
    ("No Purchased Limit", "text"),
    ("Contract Start Unknown", "text"),
    ("No Client Reports in Range", "text"),
    ("No Exceeded Clients — Healthy", "green"),
    ("Repeated Exceeded — Review", "red"),
    ("Exceeded — Monitor", "orange"),
]

ALERT_STATUS_COLORS = [
    ("Zero Usage Drop — Review Immediately", "red"),
    ("Drop Over 20% — Review", "orange"),
    ("Spike Over 20% — Review", "orange"),
    ("Stable", "green"),
    ("First Month in Range", "blue"),
    ("No Client Reports in Range", "text"),
]

TREND_ALERT_COLORS = [
    ("Growth — Good", "green"),
    ("Stable Growth", "light-green"),
    ("New — Review", "blue"),
    ("Stable Decline", "super-light-orange"),
    ("Reduction — Review", "orange"),
    ("Stale — No Growth in 3 Months", "yellow"),
    ("Stable", "text"),
]

ADOPTION_SIGNAL_COLORS = [
    ("New Use Case — Customer May Be Testing (Meeting Opportunity)", "blue"),
    ("New Type — Recently Adopted at Scale", "green"),
    ("Expanding Pilot — Discuss Scaling", "green"),
    ("Emerging — Monitor Adoption", "text"),
]

GATEWAY_STATUS_COLORS = [
    ("Active", "green"),
    ("Healthy", "green"),
    ("Running", "green"),
    ("Connected", "green"),
    ("Inactive", "red"),
    ("Disabled", "red"),
    ("Not in ObjectsReport", "text"),
    ("No Data", "text"),
]

GATEWAY_CLUSTER_COUNT_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "red", "value": None},
        {"color": "yellow", "value": 1},
        {"color": "green", "value": 2},
    ],
}

RECOMMENDATION_COLORS = [
    ("Offer Transition for Secretless Authentication", "red"),
    ("Recommend — Increase Dynamic/Rotated Secrets", "red"),
    ("Recommend — Migrate to Universal Identity", "red"),
    ("Recommend — Migrate to Cloud IAM", "red"),
    ("Recommend — Reduce API Key Share", "orange"),
    ("Acceptable Secretless Mix", "green"),
    ("Acceptable Secret Mix", "green"),
    ("Acceptable Universal Identity Mix", "green"),
    ("Acceptable Cloud IAM Mix", "green"),
    ("No Secrets Found", "text"),
    ("No API Key or Universal Identity Found", "text"),
    ("No API Key or Cloud IAM Found", "text"),
]

panel_id = 0


def next_id():
    global panel_id
    panel_id += 1
    return panel_id


def reset_ids():
    global panel_id
    panel_id = 0


def gateway_object_type_norm(column="object_type"):
    return f"LOWER(REPLACE(REPLACE(REPLACE({column}, '_', ''), '-', ''), ' ', ''))"


def gateway_cluster_match(column="object_type"):
    norm = gateway_object_type_norm(column)
    return f"""(
        {norm} LIKE '%gatewaycluster%'
        OR {norm} LIKE '%gwcluster%'
        OR {norm} LIKE '%gatorcluster%'
        OR (
            {norm} LIKE '%cluster%'
            AND ({norm} LIKE '%gateway%' OR {norm} LIKE '%gator%' OR {norm} LIKE '%gw%')
            AND {norm} NOT LIKE '%instance%'
            AND {norm} NOT LIKE '%logforward%'
        )
    )"""


def gateway_instance_match(column="object_type"):
    norm = gateway_object_type_norm(column)
    return f"""(
        {norm} LIKE '%gatewayinstance%'
        OR {norm} LIKE '%gwinstance%'
        OR {norm} LIKE '%gatorinstance%'
        OR (
            {norm} LIKE '%instance%'
            AND ({norm} LIKE '%gateway%' OR {norm} LIKE '%gator%' OR {norm} LIKE '%gw%')
            AND {norm} NOT LIKE '%logforward%'
        )
    )"""


def gateway_log_forward_match(column="object_type"):
    norm = gateway_object_type_norm(column)
    return f"""(
        {norm} LIKE '%gatewaylogforward%'
        OR {norm} LIKE '%logforward%'
        OR (
            {norm} LIKE '%forward%'
            AND ({norm} LIKE '%log%' OR {norm} LIKE '%gateway%')
        )
    )"""


def gateway_any_match(column="object_type"):
    return f"""(
        {gateway_cluster_match(column)}
        OR {gateway_instance_match(column)}
        OR {gateway_log_forward_match(column)}
    )"""


def gateway_query_replacements(column="object_type"):
    return {
        "gateway_object_type_norm": gateway_object_type_norm(column),
        "gateway_cluster_match": gateway_cluster_match(column),
        "gateway_instance_match": gateway_instance_match(column),
        "gateway_log_forward_match": gateway_log_forward_match(column),
        "gateway_any_match": gateway_any_match(column),
    }


def default_gateway_column(filename, group_by_company=False):
    if filename.startswith("gateway_stat_"):
        return "ro.object_type"
    if filename == "objects_info.sql" and not group_by_company:
        return "mod.object_type"
    if filename == "objects_info.sql" and group_by_company:
        return "ro.object_type"
    if filename == "trend_gateway_infrastructure.sql":
        return "ro.object_type"
    return "object_type"


def load_query(filename, group_by_company=False, legacy=False, **replacements):
    if legacy:
        if group_by_company:
            path = QUERIES_DIR / "legacy" / "by_company" / filename
            if not path.exists():
                path = QUERIES_DIR / "legacy" / filename
        else:
            path = QUERIES_DIR / "legacy" / filename
        if not path.exists():
            if group_by_company:
                path = QUERIES_DIR / "by_company" / filename
                if not path.exists():
                    path = QUERIES_DIR / filename
            else:
                path = QUERIES_DIR / filename
    elif group_by_company:
        path = QUERIES_DIR / "by_company" / filename
        if not path.exists():
            path = QUERIES_DIR / filename
    else:
        path = QUERIES_DIR / filename
    text = path.read_text()
    if not legacy:
        contract_col = replacements.pop("time_range_contract_col", "ahsd.current_contract_start_date")
        for key, value in time_range_sql_replacements(contract_col).items():
            replacements.setdefault(key, value)
    else:
        replacements.setdefault("period_date_cutoff", PERIOD_DATE_CUTOFF)
    if any(
        placeholder in text
        for placeholder in (
            "{gateway_cluster_match}",
            "{gateway_instance_match}",
            "{gateway_log_forward_match}",
            "{gateway_any_match}",
            "{gateway_object_type_norm}",
        )
    ):
        gateway_col = replacements.pop(
            "gateway_column",
            default_gateway_column(filename, group_by_company=group_by_company),
        )
        for key, value in gateway_query_replacements(gateway_col).items():
            replacements.setdefault(key, value)
    for key, value in replacements.items():
        text = text.replace("{" + key + "}", value)
    return text.strip()


def monthly_timeseries_field_config():
    return {
        "defaults": {
            "custom": {
                "drawStyle": "line",
                "lineInterpolation": "linear",
                "barAlignment": 0,
                "lineWidth": 1,
                "fillOpacity": 0,
                "stacking": {"mode": "normal", "group": "A"},
                "axisPlacement": "auto",
                "axisBorderShow": False,
                "scaleDistribution": {"type": "linear"},
                "showPoints": "auto",
                "pointSize": 5,
            },
            "color": {"mode": "palette-classic"},
            "mappings": [],
        },
        "overrides": [
            {
                "matcher": {"id": "byName", "options": "Used Clients"},
                "properties": [
                    {"id": "custom.drawStyle", "value": "bars"},
                    {"id": "custom.fillOpacity", "value": 100},
                    {"id": "color", "value": {"fixedColor": "blue", "mode": "fixed"}},
                ],
            },
            {
                "matcher": {"id": "byName", "options": "Exceeded Clients"},
                "properties": [
                    {"id": "custom.drawStyle", "value": "bars"},
                    {"id": "custom.fillOpacity", "value": 100},
                    {"id": "color", "value": {"fixedColor": "red", "mode": "fixed"}},
                ],
            },
            {
                "matcher": {"id": "byName", "options": "Purchased Clients"},
                "properties": [
                    {"id": "color", "value": {"fixedColor": "yellow", "mode": "fixed"}},
                    {"id": "custom.drawStyle", "value": "line"},
                    {"id": "custom.lineWidth", "value": 2},
                ],
            },
            {
                "matcher": {"id": "byName", "options": "Contract Start"},
                "properties": [
                    {"id": "custom.drawStyle", "value": "points"},
                    {"id": "custom.pointSize", "value": 19},
                    {"id": "color", "value": {"fixedColor": "text", "mode": "fixed"}},
                ],
            },
        ],
    }


def monthly_timeseries_panel(title, product, purchased_col, x, y, w=16, h=8):
    main_sql = load_query("monthly_clients_usage.sql", product=product, purchased_col=purchased_col)
    contract_sql = load_query("contract_start_marker.sql", product=product, purchased_col=purchased_col)
    return {
        "type": "timeseries",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [
            sql_target(main_sql, query_type="table", ref="A", time_columns=["time", "ts"]),
            sql_target(contract_sql, query_type="table", ref="B", time_columns=["time", "ts"]),
        ],
        "options": {
            "legend": {"showLegend": True, "displayMode": "list", "placement": "bottom", "calcs": []},
            "tooltip": {"mode": "single", "sort": "none"},
        },
        "fieldConfig": monthly_timeseries_field_config(),
        "datasource": DS,
    }


def rc_month_expr():
    return "strftime('%Y-%m', rc.report_date)"


def month_as_time():
    return f"{rc_month_expr()} || '-01T00:00:00Z' AS time"


def month_label():
    return f'{rc_month_expr()} AS "Month"'


def sql_target(raw_sql, query_type="table", ref="A", time_columns=None):
    sql = raw_sql.strip()
    return {
        "datasource": DS,
        "queryText": sql,
        "rawQueryText": sql,
        "queryType": query_type,
        "timeColumns": time_columns or [],
        "refId": ref,
    }


def row_panel(title, y, collapsed=False):
    return {
        "type": "row",
        "title": title,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": y},
        "id": next_id(),
        "collapsed": collapsed,
        "panels": [],
    }


def stat_panel(title, sql, x, y, w=4, h=4, unit=None, thresholds=None, color_mode="value"):
    fc = {
        "defaults": {
            "color": {"mode": color_mode if thresholds else "fixed", "fixedColor": "text"},
            "mappings": [],
        },
        "overrides": [],
    }
    if unit:
        fc["defaults"]["unit"] = unit
    if thresholds:
        fc["defaults"]["thresholds"] = thresholds
        fc["defaults"]["color"] = {"mode": "thresholds"}

    return {
        "type": "stat",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql)],
        "options": {
            "colorMode": "background" if thresholds else "none",
            "graphMode": "none",
            "justifyMode": "center",
            "orientation": "auto",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "/.*/", "values": True},
            "textMode": "auto",
        },
        "fieldConfig": fc,
        "datasource": DS,
    }


def gauge_panel(title, sql, x, y, w=4, h=5, thresholds=None, description=None):
    panel = {
        "type": "gauge",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql)],
        "options": {
            "minVizHeight": 75,
            "minVizWidth": 75,
            "orientation": "auto",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "/.*/", "values": True},
            "showThresholdLabels": False,
            "showThresholdMarkers": True,
        },
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "mappings": [],
                "max": 100,
                "min": 0,
                "noValue": "0%",
                "thresholds": thresholds or UTIL_THRESHOLDS,
                "unit": "percent",
            },
            "overrides": [],
        },
        "datasource": DS,
    }
    if description:
        panel["description"] = description
    return panel


def barchart_panel(title, targets, x, y, w=16, h=8, time_from=None):
    p = {
        "type": "barchart",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": targets,
        "options": {
            "barRadius": 0,
            "barWidth": 0.8,
            "fullHighlight": False,
            "groupWidth": 0.7,
            "legend": {"calcs": [], "displayMode": "list", "placement": "bottom", "showLegend": True},
            "orientation": "auto",
            "showValue": "auto",
            "stacking": "none",
            "tooltip": {"mode": "single", "sort": "none"},
            "xField": "Month",
            "xTickLabelRotation": 0,
            "xTickLabelSpacing": 0,
        },
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {"axisBorderShow": False, "axisCenteredZero": False, "drawStyle": "bars"},
                "mappings": [],
            },
            "overrides": [
                {
                    "matcher": {"id": "byName", "options": "Exceeded Clients"},
                    "properties": [{"id": "color", "value": {"fixedColor": "red", "mode": "fixed"}}],
                },
                {
                    "matcher": {"id": "byName", "options": "Purchased Clients"},
                    "properties": [
                        {"id": "custom.drawStyle", "value": "line"},
                        {"id": "custom.lineWidth", "value": 2},
                        {"id": "color", "value": {"fixedColor": "yellow", "mode": "fixed"}},
                    ],
                },
            ],
        },
        "datasource": DS,
    }
    if time_from:
        p["timeFrom"] = time_from
    return p


def timeseries_panel(title, targets, x, y, w=8, h=8, time_from="now-10d"):
    return {
        "type": "timeseries",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "timeFrom": time_from,
        "targets": targets,
        "options": {
            "legend": {"calcs": [], "displayMode": "list", "placement": "bottom", "showLegend": True},
            "tooltip": {"mode": "single", "sort": "none"},
        },
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 10},
            },
            "overrides": [],
        },
        "datasource": DS,
    }


def value_color_mappings(pairs):
    return [
        {
            "type": "value",
            "options": {
                label: {"color": color, "index": idx, "text": label}
                for idx, (label, color) in enumerate(pairs)
            },
        }
    ]


def text_status_override(field_name, pairs):
    return {
        "matcher": {"id": "byName", "options": field_name},
        "properties": [
            {"id": "custom.cellOptions", "value": {"type": "color-background", "mode": "basic"}},
            {"id": "mappings", "value": value_color_mappings(pairs)},
        ],
    }


def pct_field_override(field_name, thresholds, unit="percent"):
    return {
        "matcher": {"id": "byName", "options": field_name},
        "properties": [
            {"id": "custom.cellOptions", "value": {"type": "color-background", "mode": "gradient"}},
            {"id": "thresholds", "value": thresholds},
            {"id": "color", "value": {"mode": "thresholds"}},
            {"id": "unit", "value": unit},
        ],
    }


def piechart_panel(title, sql, x, y, w=16, h=6, label_field="Auth Method", value_field="Count"):
    return {
        "type": "piechart",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql, query_type="table")],
        "transformations": [
            {
                "id": "rowsToFields",
                "options": {
                    "mappings": [
                        {"fieldName": label_field, "handlerKey": "field.name"},
                        {"fieldName": value_field, "handlerKey": "field.value"},
                    ],
                },
            },
        ],
        "options": {
            "legend": {
                "displayMode": "table",
                "placement": "right",
                "showLegend": True,
                "values": ["value", "percent"],
            },
            "pieType": "donut",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "tooltip": {"mode": "single", "sort": "none"},
        },
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {"hideFrom": {"legend": False, "tooltip": False, "viz": False}},
            },
            "overrides": [],
        },
        "datasource": DS,
    }


def bargauge_panel(
    title,
    sql,
    x,
    y,
    w=12,
    h=6,
    orientation="horizontal",
    overrides=None,
    description=None,
    comparison=False,
):
    display_mode = "basic" if comparison else "gradient"
    value_mode = "text" if comparison else "color"
    defaults = {
        "color": {"mode": "palette-classic"},
        "mappings": [],
        "min": 0 if comparison else None,
        "thresholds": {
            "mode": "absolute",
            "steps": [{"color": "green", "value": None}] if comparison else [
                {"color": "green", "value": None},
                {"color": "red", "value": 80},
            ],
        },
    }
    panel = {
        "type": "bargauge",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql)],
        "options": {
            "displayMode": display_mode,
            "minVizHeight": 10,
            "minVizWidth": 8,
            "orientation": orientation,
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "showUnfilled": True,
            "valueMode": value_mode,
        },
        "fieldConfig": {
            "defaults": defaults,
            "overrides": overrides or [],
        },
        "datasource": DS,
    }
    if description:
        panel["description"] = description
    return panel


def table_panel(title, sql, x, y, w=24, h=8, color_field=None, overrides=None, description=None, sort_by=None):
    ovs = list(overrides or [])
    if color_field:
        ovs.append(
            {
                "matcher": {"id": "byName", "options": color_field},
                "properties": [
                    {"id": "custom.cellOptions", "value": {"type": "color-background", "mode": "gradient"}},
                    {"id": "thresholds", "value": UTIL_THRESHOLDS},
                    {"id": "color", "value": {"mode": "thresholds"}},
                    {"id": "unit", "value": "percent"},
                ],
            }
        )

    sort_by_config = []
    if sort_by:
        sort_by_config = [{"desc": sort_by[1], "displayName": sort_by[0]}]

    panel = {
        "type": "table",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql)],
        "options": {
            "cellHeight": "sm",
            "footer": {"countRows": False, "fields": "", "reducer": ["sum"], "show": False},
            "showHeader": True,
            "sortBy": sort_by_config,
        },
        "fieldConfig": {"defaults": {"custom": {"align": "auto", "cellOptions": {"type": "auto"}}}, "overrides": ovs},
        "datasource": DS,
    }
    if description:
        panel["description"] = description
    return panel


def rolling_months(count=24):
    months = []
    year, month = date.today().year, date.today().month
    for _ in range(count):
        months.append((year, month))
        month -= 1
        if month == 0:
            month = 12
            year -= 1
    return list(reversed(months))


def completed_rolling_months(count=3):
    """Last N calendar months excluding the current (incomplete) month."""
    return rolling_months(count + 1)[:-1][-count:]


def last_completed_month_end_sql():
    """Last day of the most recently completed calendar month."""
    return "strftime('%Y-%m-%d', date('now', 'start of month', '-1 day'))"


def last_full_month_sql():
    """YYYY-MM for the most recently completed calendar month."""
    return "strftime('%Y-%m', date('now', 'start of month', '-1 month'))"


def one_report_per_account_date_cte():
    return """OneReportPerAccountDate AS (
    SELECT LOWER(account_id) AS account_key, date(report_date) AS report_date, MAX(id) AS report_id
    FROM reports WHERE report_type = 'ObjectsReport'
    GROUP BY LOWER(account_id), date(report_date)
)"""


def company_accounts_filter(portfolio=False):
    if portfolio:
        return (
            f"account_id IS NOT NULL AND account_id != '' "
            f"AND {company_match_expr('name')} "
            f"AND {account_match_expr('account_id')}"
        )
    return (
        f"name = '${{company_name}}' AND account_id IS NOT NULL AND account_id != '' "
        f"AND ({ACCOUNT_ALL_CHECK} OR account_id = '${{account_id}}')"
    )


def hubspot_company_filter(portfolio=False):
    if portfolio:
        return company_match_expr("c.name")
    return "c.name = '${company_name}'"


def utilization_company_filter(portfolio=False, experimental=True):
    if portfolio:
        return (
            f"c.account_id IS NOT NULL AND c.account_id != '' "
            f"AND {company_match_expr('c.name')} "
            f"AND {account_match_expr('c.account_id')}"
        )
    if experimental:
        return (
            f"c.account_id IS NOT NULL AND c.account_id != '' "
            f"AND name = '${{company_name}}' "
            f"AND ({ACCOUNT_ALL_CHECK} OR account_id = '${{account_id}}')"
        )
    return (
        "c.account_id IS NOT NULL AND c.account_id != '' "
        "AND name = '${company_name}' "
        "AND account_id = '${account_id}'"
    )


def product_period_usage_sql(product, purchased_col, metric, portfolio=False):
    """Period usage from ObjectsReport — matches original By Customer SM Usage gauge logic."""
    cte = load_query(
        "cte_product_period_usage.sql",
        product=product,
        purchased_col=purchased_col,
        company_accounts_where=company_accounts_filter(portfolio),
        hubspot_company_filter=hubspot_company_filter(portfolio),
        time_range_contract_col="c.current_contract_start_date",
    )
    unlimited_pct = """CASE
        WHEN pt.used_plus_exceeded_total <= 100 THEN
            CASE WHEN pt.used_plus_exceeded_total * 100.0 / 500 > 100.0 THEN 100.0
                 ELSE ROUND(pt.used_plus_exceeded_total * 100.0 / 500, 2) END
        WHEN pt.used_plus_exceeded_total <= 1000 THEN
            CASE WHEN pt.used_plus_exceeded_total * 100.0 / (500 + (pt.used_plus_exceeded_total - 100) * 1.666) > 100.0 THEN 100.0
                 ELSE ROUND(pt.used_plus_exceeded_total * 100.0 / (500 + (pt.used_plus_exceeded_total - 100) * 1.666), 2) END
        WHEN pt.used_plus_exceeded_total <= 5000 THEN
            CASE WHEN pt.used_plus_exceeded_total * 100.0 / (2000 + (pt.used_plus_exceeded_total - 1000) * 0.75) > 100.0 THEN 100.0
                 ELSE ROUND(pt.used_plus_exceeded_total * 100.0 / (2000 + (pt.used_plus_exceeded_total - 1000) * 0.75), 2) END
        ELSE 100.0
    END"""

    if metric == "usage_pct":
        final = f"""
SELECT CASE
    WHEN pc.is_unlimited = 1 THEN {unlimited_pct}
    WHEN pc.purchased_monthly_total > 0
        THEN ROUND(pt.used_plus_exceeded_total * 100.0 / pc.purchased_monthly_total, 2)
    ELSE 0
END AS value
FROM PeriodTotals pt
CROSS JOIN PeriodCapacity pc
"""
    elif metric == "purchased":
        final = """
SELECT CASE
    WHEN pc.is_unlimited = 1 THEN NULL
    ELSE pc.purchased_monthly_total
END AS value
FROM PeriodCapacity pc
"""
    elif metric == "used":
        final = "SELECT pt.used_plus_exceeded_total AS value FROM PeriodTotals pt"
    elif metric == "used_only":
        final = "SELECT pt.used_total AS value FROM PeriodTotals pt"
    elif metric == "exceeded":
        final = "SELECT pt.exceeded_total AS value FROM PeriodTotals pt"
    else:
        raise ValueError(f"Unknown metric: {metric}")

    return f"{cte}\n{final}"


def objects_report_latest_usage_sql(product, portfolio=False, metric="used", purchased_col=None, experimental=True):
    """Latest ObjectsReport usage (same dedup path as original By Customer dashboard)."""
    acct = account_where_clause(portfolio, "c", experimental=experimental)
    cf = company_filter_sql(portfolio)
    purchased_select = ""
    if purchased_col:
        purchased_select = f", CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) AS purchased"
    if metric == "used":
        select_expr = "COALESCE(SUM(rcp.amount), 0)"
    elif metric == "exceeded":
        select_expr = "COALESCE(SUM(rcp.exceeded_amount), 0)"
    elif metric == "total":
        select_expr = "COALESCE(SUM(rcp.amount), 0) + COALESCE(SUM(rcp.exceeded_amount), 0)"
    elif metric == "usage_pct":
        select_expr = (
            "CASE WHEN SUM(lu.purchased) > 0 "
            "THEN ROUND(100.0 * SUM(lu.used_clients) / SUM(lu.purchased), 2) ELSE 0 END"
        )
    else:
        raise ValueError(f"Unknown metric: {metric}")

    if metric == "usage_pct":
        final_from = """
LatestUsage AS (
    SELECT cd.account_key, cd.purchased,
        COALESCE(SUM(CASE WHEN rcp.product = '{product}' THEN rcp.amount ELSE 0 END), 0) AS used_clients
    FROM CompanyData cd
    INNER JOIN LatestReportId lr ON lr.account_key = cd.account_key
    LEFT JOIN report_clients rc ON rc.report_id = lr.report_id
    LEFT JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    GROUP BY cd.account_key, cd.purchased
)
SELECT {select_expr} AS value
FROM LatestUsage lu
""".format(product=product, select_expr=select_expr)
    else:
        final_from = f"""
SELECT {select_expr} AS value
FROM LatestReportId lr
JOIN report_clients rc ON rc.report_id = lr.report_id
JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id AND rcp.product = '{product}'
"""

    return f"""
WITH CompanyData AS (
    SELECT DISTINCT LOWER(c.account_id) AS account_key{purchased_select}
    FROM companies c
    WHERE {acct} {cf}
),
{one_report_per_account_date_cte()},
LatestReportPerAccount AS (
    SELECT cd.account_key, MAX(orad.report_date) AS latest_report_date
    FROM CompanyData cd
    INNER JOIN OneReportPerAccountDate orad ON orad.account_key = cd.account_key
    WHERE date(orad.report_date) >= {TIME_RANGE_DATE_CUTOFF}
    GROUP BY cd.account_key
),
LatestReportId AS (
    SELECT lra.account_key, MAX(orad.report_id) AS report_id
    FROM LatestReportPerAccount lra
    INNER JOIN OneReportPerAccountDate orad
        ON orad.account_key = lra.account_key AND orad.report_date = lra.latest_report_date
    GROUP BY lra.account_key
)
{final_from}
"""


def account_used_subquery(product, account_id_expr, field="amount"):
    if product == "ca":
        if field != "amount":
            return "0"
        return f"""COALESCE(
            (
              SELECT SUM(rcp.amount)
              FROM report_clients rc
              JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
              WHERE rc.account_id = {account_id_expr}
                AND rcp.product = 'ca'
                AND rc.report_date = (
                  SELECT MAX(rc2.report_date) FROM report_clients rc2
                  JOIN report_clients_product_info rcp2 ON rc2.id = rcp2.report_client_id
                  WHERE rcp2.product = 'ca'
                    AND rc2.account_id = {account_id_expr}
                    AND rc2.report_date >= {TIME_RANGE_DATE_CUTOFF}
                )
            ),
            (
              SELECT SUM(ro.amount)
              FROM report_objects ro
              WHERE ro.account_id = {account_id_expr}
                AND ro.object_type LIKE '%certificate%'
                AND ro.report_date = (
                  SELECT MAX(ro2.report_date) FROM report_objects ro2
                  WHERE ro2.account_id = {account_id_expr}
                    AND ro2.report_date >= {TIME_RANGE_DATE_CUTOFF}
                )
            ),
            0
          )"""
    col = "rcp.amount" if field == "amount" else "rcp.exceeded_amount"
    return f"""COALESCE((
        SELECT SUM({col})
        FROM report_clients rc
        JOIN report_clients_product_info rcp
            ON rc.id = rcp.report_client_id AND rcp.product = '{product}'
        WHERE rc.report_id IN (
            SELECT orad.report_id
            FROM (
                SELECT MAX(r.report_date) AS latest_date
                FROM reports r
                WHERE r.report_type = 'ObjectsReport'
                  AND LOWER(r.account_id) = LOWER({account_id_expr})
                  AND date(r.report_date) >= {TIME_RANGE_DATE_CUTOFF}
            ) ld
            JOIN (
                SELECT account_id, date(report_date) AS report_date, MAX(id) AS report_id
                FROM reports
                WHERE report_type = 'ObjectsReport'
                GROUP BY account_id, date(report_date)
            ) orad ON LOWER(orad.account_id) = LOWER({account_id_expr})
                AND orad.report_date = date(ld.latest_date)
        )
    ), 0)"""


def purchased_by_company_cte(purchased_col, company_filter_sql):
    """One purchased limit per company (first account_id), matching single-account dashboard logic."""
    return f"""PurchasedByCompany AS (
    SELECT c.name AS company_name,
        CAST(COALESCE(
            (
                SELECT c2.{purchased_col}
                FROM companies c2
                WHERE c2.name = c.name
                  AND c2.account_id IS NOT NULL
                  AND c2.account_id != ''
                  AND CAST(COALESCE(c2.{purchased_col}, '0') AS INTEGER) NOT IN (999, 99999)
                ORDER BY c2.account_id
                LIMIT 1
            ),
            '0'
        ) AS INTEGER) AS clients_purchased
    FROM companies c
    WHERE {company_filter_sql}
    GROUP BY c.name
)"""


def month_column_label(year, month):
    return date(year, month, 1).strftime("%b-%y")


CLM_DAILY_CERTS_EXPR = """CASE
    WHEN (COALESCE(r.ca_self_signed, 0) - COALESCE(r.risk_expired, 0)) < 0 THEN 0
    ELSE (COALESCE(r.ca_self_signed, 0) - COALESCE(r.risk_expired, 0))
END"""


def portfolio_clm_utilization_sql(
    purchased_col, company_filter, range_start, range_end, avg_expr, pivot_cols, order_by
):
    """Multi-account CLM monthly heatmap — certificate_analysis reports (not ObjectsReport)."""
    return f"""
WITH CompanyData AS (
    SELECT DISTINCT c.name AS company_name, LOWER(c.account_id) AS account_key,
        CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) AS clients_purchased
    FROM companies c
    WHERE {company_filter}
),
DateRange AS (
    SELECT {range_start} AS range_start
),
CertificateDaily AS (
    SELECT
        cd.company_name,
        cd.account_key,
        cd.clients_purchased,
        strftime('%Y-%m', r.report_date) AS report_month,
        date(r.report_date) AS report_date,
        {CLM_DAILY_CERTS_EXPR} AS daily_certs
    FROM CompanyData cd
    INNER JOIN reports r ON LOWER(r.account_id) = cd.account_key
    WHERE r.report_type = 'certificate_analysis'
      AND date(r.report_date) >= (SELECT range_start FROM DateRange)
      AND date(r.report_date) <= date({range_end})
),
DailyMax AS (
    SELECT company_name, account_key, clients_purchased, report_month, report_date,
        MAX(daily_certs) AS daily_max
    FROM CertificateDaily
    GROUP BY company_name, account_key, clients_purchased, report_month, report_date
),
MonthlyMax AS (
    SELECT company_name, account_key, clients_purchased, report_month,
        MAX(daily_max) AS product_used
    FROM DailyMax
    GROUP BY company_name, account_key, clients_purchased, report_month
),
AggregatedByCompany AS (
    SELECT company_name, SUM(clients_purchased) AS clients_purchased, report_month,
        SUM(product_used) AS product_used_total
    FROM MonthlyMax
    GROUP BY company_name, report_month
),
FinalData AS (
    SELECT company_name, report_month,
        CASE
            WHEN clients_purchased <= 0 THEN NULL
            WHEN clients_purchased IN (999, 99999) THEN NULL
            ELSE ROUND(product_used_total * 100.0 / clients_purchased, 1)
        END AS util_pct
    FROM AggregatedByCompany
)
SELECT
    company_name AS "Customer",
    {avg_expr} AS "Avg (Last 3M)",
    {pivot_cols}
FROM FinalData
GROUP BY company_name
HAVING COUNT(util_pct) > 0
ORDER BY {order_by}
"""


def product_utilization_sql(
    product,
    purchased_col,
    portfolio=False,
    months_count=24,
    experimental=True,
    include_current_month=False,
):
    if include_current_month:
        months = rolling_months(months_count)
        range_end = "strftime('%Y-%m-%d', 'now')"
    else:
        months = completed_rolling_months(months_count) if experimental else rolling_months(months_count)
        range_end = last_completed_month_end_sql()
    avg_months = completed_rolling_months(3) if experimental else rolling_months(3)
    avg_months_sql = ", ".join(f"'{y:04d}-{m:02d}'" for y, m in avg_months)
    avg_expr = (
        f'ROUND(AVG(CASE WHEN report_month IN ({avg_months_sql}) THEN util_pct END), 1)'
    )
    pivot_cols = ", ".join([
        f"MAX(CASE WHEN report_month = '{y:04d}-{m:02d}' THEN util_pct END) AS \"{month_column_label(y, m)}\""
        for y, m in months
    ])
    order_by = '"Avg (Last 3M)" DESC' if portfolio else "company_name ASC"
    company_filter = utilization_company_filter(portfolio, experimental=experimental)

    if product == "ca" and experimental and not portfolio:
        return load_query(
            "clm_monthly_utilization.sql",
            purchased_col=purchased_col,
            company_filter=company_filter,
            purchased_by_company=purchased_by_company_cte(purchased_col, company_filter) + ",",
            avg_expr=avg_expr,
            pivot_cols=pivot_cols,
            order_by=order_by,
            time_range_contract_col="",
        )

    if product == "ca":
        used_expr = """COALESCE(
            SUM(CASE WHEN rcp.product = 'ca' THEN rcp.amount ELSE 0 END),
            (
                SELECT SUM(ro.amount)
                FROM report_objects ro
                WHERE ro.report_id = lr.report_id
                  AND ro.object_type LIKE '%certificate%'
            ),
            0
        )"""
    else:
        used_expr = f"COALESCE(SUM(CASE WHEN rcp.product = '{product}' THEN rcp.amount ELSE 0 END), 0)"

    exceeded_expr = f"COALESCE(SUM(CASE WHEN rcp.product = '{product}' THEN rcp.exceeded_amount ELSE 0 END), 0)"
    range_start = time_range_sql_replacements("")["time_range_start"]

    if portfolio and product == "ca":
        return portfolio_clm_utilization_sql(
            purchased_col, company_filter, range_start, range_end, avg_expr, pivot_cols, order_by
        )

    if portfolio:
        return f"""
WITH CompanyData AS (
    SELECT DISTINCT c.name AS company_name, LOWER(c.account_id) AS account_key,
        CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) AS clients_purchased
    FROM companies c
    WHERE {company_filter}
),
DateRange AS (
    SELECT {range_start} AS range_start
),
OneReportPerAccountDate AS (
    SELECT cd.account_key, date(r.report_date) AS report_date, MAX(r.id) AS report_id
    FROM reports r
    INNER JOIN CompanyData cd ON cd.account_key = LOWER(r.account_id)
    WHERE r.report_type = 'ObjectsReport'
    GROUP BY cd.account_key, date(r.report_date)
),
MonthlyLatest AS (
    SELECT cd.company_name, cd.account_key, cd.clients_purchased,
        strftime('%Y-%m', orad.report_date) AS report_month,
        MAX(orad.report_date) AS latest_report_date
    FROM CompanyData cd
    INNER JOIN OneReportPerAccountDate orad ON orad.account_key = cd.account_key
    WHERE date(orad.report_date) >= (SELECT range_start FROM DateRange)
      AND date(orad.report_date) <= date({range_end})
    GROUP BY cd.company_name, cd.account_key, cd.clients_purchased, strftime('%Y-%m', orad.report_date)
),
LatestReportId AS (
    SELECT ml.company_name, ml.account_key, ml.clients_purchased, ml.report_month,
        MAX(orad.report_id) AS report_id
    FROM MonthlyLatest ml
    INNER JOIN OneReportPerAccountDate orad
        ON orad.account_key = ml.account_key AND orad.report_date = ml.latest_report_date
    GROUP BY ml.company_name, ml.account_key, ml.clients_purchased, ml.report_month
),
MonthlyUsage AS (
    SELECT lr.company_name, lr.clients_purchased, lr.report_month,
        {used_expr} AS product_used,
        {exceeded_expr} AS product_exceeded
    FROM LatestReportId lr
    LEFT JOIN report_clients rc ON rc.report_id = lr.report_id
    LEFT JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    GROUP BY lr.company_name, lr.clients_purchased, lr.report_month, lr.report_id
),
AggregatedByCompany AS (
    SELECT company_name, SUM(clients_purchased) AS clients_purchased, report_month,
        SUM(product_used) AS product_used_total,
        SUM(product_exceeded) AS product_exceeded_total
    FROM MonthlyUsage
    GROUP BY company_name, report_month
),
FinalData AS (
    SELECT company_name, report_month,
        CASE
            WHEN clients_purchased <= 0 THEN NULL
            WHEN clients_purchased IN (999, 99999) THEN NULL
            ELSE ROUND(
                (product_used_total + product_exceeded_total) * 100.0 / clients_purchased,
                1
            )
        END AS util_pct
    FROM AggregatedByCompany
)
SELECT
    company_name AS "Customer",
    {avg_expr} AS "Avg (Last 3M)",
    {pivot_cols}
FROM FinalData
GROUP BY company_name
HAVING COUNT(util_pct) > 0
ORDER BY {order_by}
"""

    return f"""
WITH CompanyData AS (
    SELECT DISTINCT c.name AS company_name, LOWER(c.account_id) AS account_key
    FROM companies c
    WHERE {company_filter}
),
{purchased_by_company_cte(purchased_col, company_filter)},
DateRange AS (
    SELECT {range_start} AS range_start
),
OneReportPerAccountDate AS (
    SELECT cd.account_key, date(r.report_date) AS report_date, MAX(r.id) AS report_id
    FROM reports r
    INNER JOIN CompanyData cd ON cd.account_key = LOWER(r.account_id)
    WHERE r.report_type = 'ObjectsReport'
    GROUP BY cd.account_key, date(r.report_date)
),
MonthlyLatest AS (
    SELECT cd.company_name, cd.account_key,
        strftime('%Y-%m', orad.report_date) AS report_month,
        MAX(orad.report_date) AS latest_report_date
    FROM CompanyData cd
    INNER JOIN OneReportPerAccountDate orad ON orad.account_key = cd.account_key
    WHERE date(orad.report_date) >= (SELECT range_start FROM DateRange)
      AND date(orad.report_date) <= date({range_end})
    GROUP BY cd.company_name, cd.account_key, strftime('%Y-%m', orad.report_date)
),
LatestReportId AS (
    SELECT ml.company_name, ml.account_key, ml.report_month,
        MAX(orad.report_id) AS report_id
    FROM MonthlyLatest ml
    INNER JOIN OneReportPerAccountDate orad
        ON orad.account_key = ml.account_key AND orad.report_date = ml.latest_report_date
    GROUP BY ml.company_name, ml.account_key, ml.report_month
),
MonthlyUsageByAccount AS (
    SELECT lr.company_name, lr.account_key, lr.report_month,
        {used_expr} AS product_used,
        {exceeded_expr} AS product_exceeded
    FROM LatestReportId lr
    LEFT JOIN report_clients rc ON rc.report_id = lr.report_id
    LEFT JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
    GROUP BY lr.company_name, lr.account_key, lr.report_month, lr.report_id
),
AggregatedByCompany AS (
    SELECT company_name, report_month,
        SUM(product_used) AS product_used_total,
        SUM(product_exceeded) AS product_exceeded_total
    FROM MonthlyUsageByAccount
    GROUP BY company_name, report_month
),
FinalData AS (
    SELECT abc.company_name, abc.report_month,
        CASE
            WHEN pbc.clients_purchased <= 0 THEN NULL
            WHEN pbc.clients_purchased IN (999, 99999) THEN NULL
            ELSE ROUND(
                (abc.product_used_total + abc.product_exceeded_total) * 100.0 / pbc.clients_purchased,
                1
            )
        END AS util_pct
    FROM AggregatedByCompany abc
    INNER JOIN PurchasedByCompany pbc ON pbc.company_name = abc.company_name
)
SELECT
    company_name AS "Customer",
    {avg_expr} AS "Avg (Last 3M)",
    {pivot_cols}
FROM FinalData
GROUP BY company_name
ORDER BY {order_by}
"""


def product_utilization_table_panel(
    title,
    product,
    purchased_col,
    portfolio=False,
    x=0,
    y=0,
    w=24,
    h=10,
    experimental=True,
    months_count=24,
    include_current_month=False,
):
    sql = product_utilization_sql(
        product,
        purchased_col,
        portfolio=portfolio,
        experimental=experimental,
        months_count=months_count,
        include_current_month=include_current_month,
    )
    return {
        "type": "table",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql, query_type="table")],
        "options": {
            "cellHeight": "sm",
            "footer": {"countRows": False, "fields": "", "reducer": ["sum"], "show": False},
            "showHeader": True,
            "sortBy": [{"desc": True, "displayName": "Avg (Last 3M)"}],
        },
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "custom": {
                    "align": "center",
                    "cellOptions": {"type": "color-background", "applyToRow": False, "wrapText": True},
                    "inspect": False,
                    "filterable": False,
                    "minWidth": 80,
                },
                "decimals": 1,
                "mappings": [],
                "thresholds": SM_UTIL_THRESHOLDS,
                "unit": "percent",
            },
            "overrides": [
                {
                    "matcher": {"id": "byName", "options": "Customer"},
                    "properties": [
                        {"id": "custom.cellOptions", "value": {"type": "auto", "wrapText": True}},
                        {"id": "custom.width", "value": 200},
                        {"id": "unit", "value": "string"},
                        {"id": "color", "value": {"mode": "fixed", "fixedColor": "text"}},
                    ],
                },
                {
                    "matcher": {"id": "byName", "options": "Avg (Last 3M)"},
                    "properties": [
                        {"id": "custom.width", "value": 110},
                        {"id": "custom.cellOptions", "value": {"mode": "gradient", "type": "color-background"}},
                    ],
                },
            ],
        },
        "datasource": DS,
    }


def sm_utilization_sql(portfolio=False, months_count=24):
    return product_utilization_sql("sm", "clients_sm", portfolio=portfolio, months_count=months_count)


def sm_utilization_table_panel(title, portfolio=False, x=0, y=0, w=24, h=12):
    return product_utilization_table_panel(
        title, "sm", "clients_sm", portfolio=portfolio, x=x, y=y, w=w, h=h
    )


def sm_utilization_section(y, portfolio=False):
    """Deprecated: utilization tables are embedded in each product section."""
    return [], y


def heatmap_panel(title, sql, x, y, w=24, h=10):
    return {
        "type": "heatmap",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql, query_type="table")],
        "options": {
            "calculate": False,
            "cellGap": 1,
            "color": {
                "exponent": 0.5,
                "fill": "dark-orange",
                "mode": "scheme",
                "reverse": False,
                "scale": "exponential",
                "scheme": "RdYlGn",
                "steps": 128,
            },
            "exemplars": {"color": "rgba(255,0,255,0.7)"},
            "filterValues": {"le": 1e-9},
            "legend": {"show": True},
            "rowsFrame": {"layout": "auto"},
            "tooltip": {"show": True, "yHistogram": False},
            "yAxis": {"axisPlacement": "left", "reverse": False},
        },
        "fieldConfig": {"defaults": {}, "overrides": []},
        "datasource": DS,
    }


def account_filter_sql(portfolio=False):
    if portfolio:
        return f"AND {account_match_expr('rc.account_id')}"
    return f"AND ({ACCOUNT_ALL_CHECK} OR rc.account_id = '${{account_id}}')"


def company_filter_sql(portfolio=False, alias="c"):
    if portfolio:
        return f"AND {company_match_expr(f'{alias}.name')}"
    return ""


def account_where_clause(portfolio=False, alias="", experimental=True):
    col = f"{alias}." if alias else ""
    if portfolio:
        return (
            f"{col}account_id IS NOT NULL "
            f"AND {account_match_expr(f'{col}account_id')} "
            f"AND {company_match_expr(f'{col}name')}"
        )
    if experimental:
        return (
            f"{col}account_id IS NOT NULL "
            f"AND {col}name = '${{company_name}}' "
            f"AND ({ACCOUNT_ALL_CHECK} OR {col}account_id = '${{account_id}}')"
        )
    return (
        f"{col}account_id IS NOT NULL "
        f"AND {col}name = '${{company_name}}' "
        f"AND {col}account_id = '${{account_id}}'"
    )


def product_usage_pct_sql(label, product, purchased_col, portfolio=False, experimental=True):
    if product == "ca":
        return clm_usage_pct_sql(portfolio)
    if experimental:
        return product_period_usage_sql(product, purchased_col, "usage_pct", portfolio=portfolio)
    return objects_report_latest_usage_sql(
        product, portfolio=portfolio, metric="usage_pct", purchased_col=purchased_col, experimental=experimental
    )


def clm_used_sql(portfolio=False):
    acct = account_where_clause(portfolio, "c")
    cf = company_filter_sql(portfolio)
    return f"""
SELECT COALESCE(
  (
    SELECT SUM(rcp.amount)
    FROM report_clients rc
    JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
    WHERE rc.account_id = c.account_id
      AND rcp.product = 'ca'
      AND rc.report_date = (
        SELECT MAX(rc2.report_date) FROM report_clients rc2
        JOIN report_clients_product_info rcp2 ON rc2.id = rcp2.report_client_id
        WHERE rcp2.product = 'ca'
          AND rc2.account_id = c.account_id
          AND rc2.report_date >= {TIME_RANGE_DATE_CUTOFF}
      )
  ),
  (
    SELECT SUM(ro.amount)
    FROM report_objects ro
    WHERE ro.account_id = c.account_id
      AND ro.object_type LIKE '%certificate%'
      AND ro.report_date = (
        SELECT MAX(ro2.report_date) FROM report_objects ro2
        WHERE ro2.account_id = c.account_id
          AND ro2.report_date >= {TIME_RANGE_DATE_CUTOFF}
      )
  ),
  0
) AS value
FROM companies c
WHERE {acct} {cf}
LIMIT 1
"""


def clm_usage_pct_sql(portfolio=False):
    acct = account_where_clause(portfolio, "c")
    cf = company_filter_sql(portfolio)
    return f"""
SELECT CASE WHEN CAST(c.clients_ca AS INTEGER) > 0
  THEN ROUND(100.0 * COALESCE(
    (
      SELECT SUM(rcp.amount)
      FROM report_clients rc
      JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
      WHERE rc.account_id = c.account_id
        AND rcp.product = 'ca'
        AND rc.report_date = (
          SELECT MAX(rc2.report_date) FROM report_clients rc2
          JOIN report_clients_product_info rcp2 ON rc2.id = rcp2.report_client_id
          WHERE rcp2.product = 'ca'
            AND rc2.account_id = c.account_id
            AND rc2.report_date >= {TIME_RANGE_DATE_CUTOFF}
        )
    ),
    (
      SELECT SUM(ro.amount)
      FROM report_objects ro
      WHERE ro.account_id = c.account_id
        AND ro.object_type LIKE '%certificate%'
        AND ro.report_date = (
          SELECT MAX(ro2.report_date) FROM report_objects ro2
          WHERE ro2.account_id = c.account_id
            AND ro2.report_date >= {TIME_RANGE_DATE_CUTOFF}
        )
    ),
    0
  ) / CAST(c.clients_ca AS INTEGER), 2)
  ELSE 0 END AS value
FROM companies c
WHERE {acct} {cf}
LIMIT 1
"""


def product_purchased_sql(purchased_col, portfolio=False, product="sm", experimental=True):
    if product == "ca" or not experimental:
        where = account_where_clause(portfolio, experimental=experimental)
        cf = company_filter_sql(portfolio, "companies")
        return f"""
SELECT COALESCE(SUM(CAST({purchased_col} AS INTEGER)), 0) AS value
FROM companies
WHERE {where} {cf}
"""
    return product_period_usage_sql(product, purchased_col, "purchased", portfolio=portfolio)


def product_used_sql(product, portfolio=False, purchased_col="clients_sm", experimental=True):
    if product == "ca":
        return clm_used_sql(portfolio)
    if experimental:
        return product_period_usage_sql(product, purchased_col, "used_only", portfolio=portfolio)
    return objects_report_latest_usage_sql(product, portfolio=portfolio, metric="used", experimental=experimental)


def product_total_used_sql(product, portfolio=False, purchased_col="clients_sm", experimental=True):
    if product == "ca":
        return clm_used_sql(portfolio)
    if experimental:
        return product_period_usage_sql(product, purchased_col, "used", portfolio=portfolio)
    return objects_report_latest_usage_sql(product, portfolio=portfolio, metric="total", experimental=experimental)


def product_exceeded_sql(product, portfolio=False, purchased_col="clients_sm", experimental=True):
    if product == "ca" or not experimental:
        return "SELECT 0 AS value"
    return product_period_usage_sql(product, purchased_col, "exceeded", portfolio=portfolio)


def multi_account_clm_summary_metrics_cte():
    """Last full month CLM used count from certificate_analysis (matches original By Customer CLM chart)."""
    return f"""
LastFullMonth AS (
  SELECT strftime('%Y-%m', date('now', 'start of month', '-1 month')) AS report_month
),
CertificateDaily AS (
  SELECT fa.name, fa.account_id, fa.purchased,
    date(r.report_date) AS report_date,
    {CLM_DAILY_CERTS_EXPR} AS daily_certs
  FROM FilteredAccounts fa
  INNER JOIN reports r ON LOWER(r.account_id) = fa.account_key
  WHERE r.report_type = 'certificate_analysis'
    AND strftime('%Y-%m', r.report_date) = (SELECT report_month FROM LastFullMonth)
),
DailyMax AS (
  SELECT name, account_id, purchased, report_date,
    MAX(daily_certs) AS daily_max
  FROM CertificateDaily
  GROUP BY name, account_id, purchased, report_date
),
MonthlyUsed AS (
  SELECT name, account_id, purchased,
    MAX(daily_max) AS used
  FROM DailyMax
  GROUP BY name, account_id, purchased
),
AccountMetrics AS (
  SELECT fa.name, fa.account_id, fa.purchased,
    COALESCE(mu.used, 0) AS used_in_limit,
    0 AS exceeded,
    COALESCE(mu.used, 0) AS total_used
  FROM FilteredAccounts fa
  LEFT JOIN MonthlyUsed mu ON mu.account_id = fa.account_id
)"""


def multi_account_summary_metrics_cte(product):
    """Last completed calendar month — ObjectsReport for SM/SRA/PWM; certificate_analysis for CLM."""
    if product == "ca":
        return multi_account_clm_summary_metrics_cte()

    used_expr = f"COALESCE(SUM(CASE WHEN rcp.product = '{product}' THEN rcp.amount ELSE 0 END), 0)"
    exceeded_expr = f"COALESCE(SUM(CASE WHEN rcp.product = '{product}' THEN rcp.exceeded_amount ELSE 0 END), 0)"

    return f"""
LastFullMonth AS (
  SELECT strftime('%Y-%m', date('now', 'start of month', '-1 month')) AS report_month
),
OneReportPerAccountDate AS (
  SELECT fa.account_key, date(r.report_date) AS report_date, MAX(r.id) AS report_id
  FROM reports r
  INNER JOIN FilteredAccounts fa ON fa.account_key = LOWER(r.account_id)
  WHERE r.report_type = 'ObjectsReport'
    AND strftime('%Y-%m', r.report_date) = (SELECT report_month FROM LastFullMonth)
  GROUP BY fa.account_key, date(r.report_date)
),
LatestReportInMonth AS (
  SELECT fa.account_key, fa.name, fa.account_id, fa.purchased,
    MAX(orad.report_date) AS latest_report_date
  FROM FilteredAccounts fa
  LEFT JOIN OneReportPerAccountDate orad ON orad.account_key = fa.account_key
  GROUP BY fa.account_key, fa.name, fa.account_id, fa.purchased
),
LatestReportId AS (
  SELECT lrm.name, lrm.account_id, lrm.purchased, MAX(orad.report_id) AS report_id
  FROM LatestReportInMonth lrm
  LEFT JOIN OneReportPerAccountDate orad
    ON orad.account_key = lrm.account_key AND orad.report_date = lrm.latest_report_date
  GROUP BY lrm.name, lrm.account_id, lrm.purchased
),
AccountMetrics AS (
  SELECT lr.name, lr.account_id, lr.purchased,
    CASE
      WHEN lr.report_id IS NULL THEN 0
      ELSE {used_expr}
    END AS used_in_limit,
    CASE
      WHEN lr.report_id IS NULL THEN 0
      ELSE {exceeded_expr}
    END AS exceeded,
    CASE
      WHEN lr.report_id IS NULL THEN 0
      ELSE ({used_expr} + {exceeded_expr})
    END AS total_used
  FROM LatestReportId lr
  LEFT JOIN report_clients rc ON rc.report_id = lr.report_id
  LEFT JOIN report_clients_product_info rcp ON rcp.report_client_id = rc.id
  GROUP BY lr.name, lr.account_id, lr.purchased, lr.report_id
)"""


def product_summary_by_customer_sql(product, purchased_col, group_by_company=False):
    acct = account_where_clause(True, "c")
    used_expr = account_used_subquery(product, "c.account_id", "amount")
    exceeded_expr = account_used_subquery(product, "c.account_id", "exceeded")

    if group_by_company:
        return f"""
WITH FilteredAccounts AS (
  SELECT
    c.name,
    c.account_id,
    LOWER(c.account_id) AS account_key,
    CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) AS purchased
  FROM companies c
  WHERE {acct}
),
{multi_account_summary_metrics_cte(product)}
SELECT
  name AS "Customer",
  COUNT(DISTINCT account_id) AS "Accounts",
  GROUP_CONCAT(DISTINCT account_id) AS "Account IDs",
  SUM(purchased) AS "Purchased",
  SUM(used_in_limit) AS "Used Clients",
  SUM(exceeded) AS "Exceeded",
  SUM(total_used) AS "Total Clients including Exceeding",
  CASE
    WHEN SUM(purchased) IN (0, 999, 99999) THEN NULL
    WHEN SUM(purchased) <= 0 THEN NULL
    ELSE ROUND(100.0 * SUM(total_used) / SUM(purchased), 1)
  END AS "Usage %"
FROM AccountMetrics
GROUP BY name
ORDER BY name
"""

    return f"""
SELECT
  c.name AS "Customer",
  c.account_id AS "Account ID",
  CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) AS "Purchased",
  {used_expr} AS "Used Clients",
  {exceeded_expr} AS "Exceeded",
  ({used_expr}) + ({exceeded_expr}) AS "Total Clients including Exceeding",
  CASE
    WHEN CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) IN (0, 999, 99999) THEN NULL
    WHEN CAST(COALESCE(c.{purchased_col}, '0') AS INTEGER) <= 0 THEN NULL
    ELSE ROUND(100.0 * (({used_expr}) + ({exceeded_expr})) / CAST(c.{purchased_col} AS INTEGER), 1)
  END AS "Usage %"
FROM companies c
WHERE {acct}
ORDER BY c.name, c.account_id
"""


def product_summary_table_panel(
    title, product, purchased_col, x=0, y=0, w=24, h=8, group_by_company=False
):
    sql = product_summary_by_customer_sql(product, purchased_col, group_by_company=group_by_company)
    return table_panel(
        title,
        sql,
        x,
        y,
        w=w,
        h=h,
        overrides=[pct_field_override("Usage %", UTIL_THRESHOLDS)],
    )


def product_capacity_bargauge_sql(product, purchased_col, portfolio=False):
    acct = account_where_clause(portfolio, "c")
    cf = company_filter_sql(portfolio)
    if product == "ca":
        used_expr = """COALESCE(
            (
              SELECT SUM(rcp.amount)
              FROM report_clients rc
              JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
              WHERE rc.account_id = c.account_id
                AND rcp.product = 'ca'
                AND rc.report_date = (
                  SELECT MAX(rc2.report_date) FROM report_clients rc2
                  JOIN report_clients_product_info rcp2 ON rc2.id = rcp2.report_client_id
                  WHERE rcp2.product = 'ca'
                    AND rc2.account_id = c.account_id
                    AND rc2.report_date >= {TIME_RANGE_DATE_CUTOFF}
                )
            ),
            (
              SELECT SUM(ro.amount)
              FROM report_objects ro
              WHERE ro.account_id = c.account_id
                AND ro.object_type LIKE '%certificate%'
                AND ro.report_date = (
                  SELECT MAX(ro2.report_date) FROM report_objects ro2
                  WHERE ro2.account_id = c.account_id
                    AND ro2.report_date >= {TIME_RANGE_DATE_CUTOFF}
                )
            ),
            0
          )"""
    else:
        used_expr = f"""COALESCE((
            SELECT SUM(rcp.amount)
            FROM report_clients rc
            JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
            WHERE rc.account_id = c.account_id
              AND rcp.product = '{product}'
              AND rc.report_date = (
                SELECT MAX(rc2.report_date) FROM report_clients rc2
                JOIN report_clients_product_info rcp2 ON rc2.id = rcp2.report_client_id
                WHERE rcp2.product = '{product}'
                  AND rc2.account_id = c.account_id
                  AND rc2.report_date >= {TIME_RANGE_DATE_CUTOFF}
              )
          ), 0)"""
    return f"""
SELECT
  {used_expr} AS "Used",
  COALESCE(CAST(c.{purchased_col} AS INTEGER), 0) AS "Purchased"
FROM companies c
WHERE {acct} {cf}
LIMIT 1
"""


def capacity_bargauge_overrides():
    return [
        {
            "matcher": {"id": "byName", "options": "Used"},
            "properties": [{"id": "color", "value": {"fixedColor": "green", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "Purchased"},
            "properties": [{"id": "color", "value": {"fixedColor": "#5794F2", "mode": "fixed"}}],
        },
    ]


def auth_method_mix_overrides(comparison=False):
    scale_props = [{"id": "min", "value": 0}] if comparison else []
    return [
        {
            "matcher": {"id": "byName", "options": "Static Credentials"},
            "properties": [
                *scale_props,
                {"id": "color", "value": {"fixedColor": "red", "mode": "fixed"}},
            ],
        },
        {
            "matcher": {"id": "byName", "options": "Secretless"},
            "properties": [
                *scale_props,
                {"id": "color", "value": {"fixedColor": "green", "mode": "fixed"}},
            ],
        },
        {
            "matcher": {"id": "byName", "options": "API Key"},
            "properties": [{"id": "color", "value": {"fixedColor": "red", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "Universal Identity"},
            "properties": [{"id": "color", "value": {"fixedColor": "green", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "AWS IAM"},
            "properties": [{"id": "color", "value": {"fixedColor": "blue", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "Azure AD"},
            "properties": [{"id": "color", "value": {"fixedColor": "purple", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "GCP"},
            "properties": [{"id": "color", "value": {"fixedColor": "yellow", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "Cloud IAM (AWS + Azure + GCP)"},
            "properties": [{"id": "color", "value": {"fixedColor": "blue", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "Preferred (UID or Secretless)"},
            "properties": [{"id": "color", "value": {"fixedColor": "green", "mode": "fixed"}}],
        },
        {
            "matcher": {"id": "byName", "options": "Preferred (UI + Cloud IAM + JWT)"},
            "properties": [{"id": "color", "value": {"fixedColor": "green", "mode": "fixed"}}],
        },
    ]


def product_avg_usage_sql(product, purchased_col, portfolio=False, experimental=True):
    if product == "ca" and experimental:
        inner = load_query(
            "clm_monthly_util_pct.sql",
            purchased_col=purchased_col,
            company_filter=utilization_company_filter(portfolio, experimental=experimental),
            time_range_contract_col="",
        )
    else:
        inner = load_query(
            "monthly_utilization.sql",
            product=product,
            purchased_col=purchased_col,
            legacy=not experimental,
            time_range_end=last_completed_month_end_sql(),
        )
    return f'SELECT ROUND(AVG("Utilization %"), 1) AS value FROM ({inner})'


def monthly_util_table_sql(product, purchased_col, portfolio=False):
    return load_query(
        "monthly_utilization.sql",
        product=product,
        purchased_col=purchased_col,
        time_range_end=last_completed_month_end_sql(),
    )


def last_10_days_targets(product, portfolio=False):
    cf = company_filter_sql(portfolio)
    filt = account_filter_sql(portfolio)
    sql = f"""
SELECT rc.report_date || 'T00:00:00Z' AS time,
  SUM(rcp.amount) AS "Used Clients",
  SUM(rcp.exceeded_amount) AS "Exceeded Clients"
FROM report_clients rc
JOIN report_clients_product_info rcp ON rc.id = rcp.report_client_id
JOIN companies c ON c.account_id = rc.account_id
WHERE rcp.product = '{product}'
  {filt} {cf}
  AND rc.report_date >= date('now', '-10 days')
GROUP BY rc.report_date
ORDER BY rc.report_date
"""
    return [sql_target(sql, query_type="time series", ref="A", time_columns=["time"])]


SLA_HEADER_THRESHOLDS = {
    "mode": "absolute",
    "steps": [
        {"color": "green", "value": None},
        {"color": "red", "value": 80},
    ],
}

SLA_VALUE_MAPPINGS = [
    {
        "options": {
            "Gold": {"color": "#ffd700", "index": 1, "text": "Gold"},
            "Platinum": {"color": "#e5e4e2", "index": 0, "text": "Platinum"},
        },
        "type": "value",
    }
]

HEADER_TABLE_FIELD_CONFIG = {
    "defaults": {
        "custom": {"align": "auto", "cellOptions": {"type": "auto"}, "inspect": False},
        "mappings": [],
        "thresholds": SLA_HEADER_THRESHOLDS,
        "color": {"mode": "thresholds"},
    },
    "overrides": [],
}

HEADER_TABLE_OPTIONS = {
    "showHeader": True,
    "cellHeight": "sm",
    "footer": {"show": False, "reducer": ["sum"], "countRows": False, "fields": ""},
}


def header_table_panel(sql, x, y, w, title="", align="auto"):
    fc = dict(HEADER_TABLE_FIELD_CONFIG)
    fc["defaults"] = dict(fc["defaults"])
    fc["defaults"]["custom"] = dict(fc["defaults"]["custom"])
    fc["defaults"]["custom"]["align"] = align
    panel = {
        "type": "table",
        "gridPos": {"h": 3, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql)],
        "options": HEADER_TABLE_OPTIONS,
        "fieldConfig": fc,
        "datasource": DS,
    }
    if title:
        panel["title"] = title
    return panel


def header_account_ids_panel(x, y, w=2):
    """One account ID per row — readable at fixed table font size (no stat auto-shrink)."""
    return {
        "type": "table",
        "title": "Account IDs",
        "gridPos": {"h": 3, "w": w, "x": x, "y": y},
        "id": next_id(),
        "targets": [sql_target(load_query("account_ids.sql"))],
        "options": {
            "showHeader": False,
            "cellHeight": "sm",
            "footer": {"show": False, "reducer": ["sum"], "countRows": False, "fields": ""},
            "sortBy": [],
        },
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "align": "auto",
                    "cellOptions": {"type": "auto", "wrapText": False},
                    "inspect": False,
                    "filterable": False,
                },
                "color": {"fixedColor": "text", "mode": "fixed"},
                "mappings": [],
            },
            "overrides": [],
        },
        "datasource": DS,
    }


HOME_BUTTON_HTML = """<div style="
  display:flex;
  align-items:center;
  justify-content:center;
  height:100%;
">
  <a href="https://akeyless-analytics.com/d/af7l8pm3w7e9sd/v2-draft-all-customer?orgId=1"
   target="_blank"
   style="
     display:inline-flex;
     align-items:center;
     justify-content:center;
     padding:12px 22px;
     font-size:16px;
     font-weight:600;
     border:1.5px solid #ccc;
     border-radius:8px;
     text-decoration:none;
   ">
  ⌂ Home
</a>

</div>
"""


def original_account_header_panels(y=0):
    """Top header row matching the original By Customer dashboard."""
    sla_sql = load_query("account_sla.sql")
    panels = [
        {
            "type": "text",
            "gridPos": {"h": 3, "w": 2, "x": 0, "y": y},
            "id": next_id(),
            "options": {
                "mode": "html",
                "code": {"language": "plaintext", "showLineNumbers": False, "showMiniMap": False},
                "content": HOME_BUTTON_HTML,
            },
            "datasource": DS,
        },
        {
            "type": "stat",
            "title": "SLA",
            "gridPos": {"h": 3, "w": 2, "x": 2, "y": y},
            "id": next_id(),
            "targets": [sql_target(sla_sql)],
            "options": {
                "reduceOptions": {
                    "values": False,
                    "calcs": ["lastNotNull"],
                    "fields": "/^account_support_level$/",
                },
                "orientation": "auto",
                "textMode": "auto",
                "wideLayout": True,
                "colorMode": "background",
                "graphMode": "area",
                "justifyMode": "auto",
                "showPercentChange": False,
                "percentChangeColorMode": "standard",
            },
            "fieldConfig": {
                "defaults": {
                    "mappings": [],
                    "thresholds": SLA_HEADER_THRESHOLDS,
                    "color": {"mode": "thresholds"},
                },
                "overrides": [
                    {
                        "matcher": {"id": "byName", "options": "account_support_level"},
                        "properties": [{"id": "mappings", "value": SLA_VALUE_MAPPINGS}],
                    }
                ],
            },
            "datasource": DS,
        },
        header_account_ids_panel(x=4, y=y),
        {
            "type": "text",
            "gridPos": {"h": 3, "w": 4, "x": 6, "y": y},
            "id": next_id(),
            "options": {
                "mode": "html",
                "code": {"language": "plaintext", "showLineNumbers": False, "showMiniMap": False},
                "content": (
                    '<div style="text-align: center; font-size: 36px; font-weight: bold; '
                    'display: flex; align-items: center; justify-content: center; height: 100%;">\n'
                    "${company_name}\n</div>"
                ),
            },
            "targets": [
                sql_target(
                    "SELECT name AS \"Company Name\" FROM companies WHERE name = '${company_name}' LIMIT 1;"
                )
            ],
            "datasource": DS,
        },
        header_table_panel(
            load_query("account_contract_info.sql"),
            x=10,
            y=y,
            w=8,
            align="center",
        ),
        header_table_panel(load_query("account_owners.sql"), x=18, y=y, w=6, align="center"),
    ]
    return panels, y + 3


def account_details_panels(y, portfolio=False, experimental=True):
    where = account_where_clause(portfolio, experimental=experimental)
    cf = company_filter_sql(portfolio, "companies")
    base = f"FROM companies WHERE {where} {cf} LIMIT 1"

    if portfolio:
        account_id_sql = f"SELECT account_id AS value {base}"
        company_sql = f"SELECT name AS value {base}"
        sla_sql = f"SELECT 'N/A' AS value {base}"
    elif experimental:
        account_id_sql = """
SELECT COALESCE(
  CASE
    WHEN '${account_id:raw}' IN ('All', '%', '$__all') OR LOWER('${account_id:raw}') = 'all'
      THEN (SELECT GROUP_CONCAT(DISTINCT account_id) FROM companies WHERE name = '${company_name}' AND account_id IS NOT NULL)
    ELSE (SELECT account_id FROM companies WHERE account_id = '${account_id}' LIMIT 1)
  END,
  '${account_id}'
) AS value
"""
    else:
        account_id_sql = """
SELECT COALESCE(
  (SELECT account_id FROM companies WHERE account_id = '${account_id}' LIMIT 1),
  '${account_id}'
) AS value
"""
        company_sql = """
SELECT COALESCE(
  (SELECT name FROM companies WHERE account_id = '${account_id}' LIMIT 1),
  '${company_name}'
) AS value
"""
        sla_sql = "SELECT 'N/A' AS value FROM companies WHERE account_id = '${account_id}' LIMIT 1"

    panels = [
        stat_panel("SLA", sla_sql, 0, y, w=3),
        stat_panel("Account ID(s)", account_id_sql, 3, y, w=4),
        stat_panel("Company Name", company_sql, 7, y, w=5),
        stat_panel(
            "Contract Start Date",
            f"SELECT COALESCE(current_contract_start_date, 'N/A') AS value {base}",
            12,
            y,
            w=3,
        ),
        stat_panel("Contract End Date", f"SELECT 'N/A' AS value {base}", 15, y, w=3),
        stat_panel(
            "Days Since Contract Start",
            f"""
SELECT CAST(julianday('now') - julianday(current_contract_start_date) AS INTEGER) AS value
{base}
""",
            18,
            y,
            w=3,
        ),
        stat_panel("CSM", f"SELECT 'N/A' AS value {base}", 21, y, w=3),
    ]
    y2 = y + 4
    na_base = base if portfolio else "FROM companies WHERE account_id = '${account_id}' LIMIT 1"
    panels.extend(
        [
            stat_panel("CSE", f"SELECT 'N/A' AS value {na_base}", 0, y2, w=6),
            stat_panel("Sales Executive", f"SELECT 'N/A' AS value {na_base}", 6, y2, w=6),
        ]
    )
    return panels, y2 + 4


def product_section(label, product, purchased_col, y, portfolio=False, multi_account=False, experimental=True):
    panels = [row_panel(f"{label} — {product_label_full(label)}", y)]
    y += 1
    use_portfolio_sql = portfolio or multi_account

    if multi_account:
        panels.append(
            product_summary_table_panel(
                f"{label} — Summary by Customer",
                product,
                purchased_col,
                x=0,
                y=y,
                h=8,
                group_by_company=True,
            )
        )
        y += 8
    else:
        if product == "ca":
            pct_sql = clm_usage_pct_sql(portfolio)
            used_sql = clm_used_sql(portfolio)
        else:
            pct_sql = product_usage_pct_sql(label, product, purchased_col, portfolio, experimental=experimental)
            used_sql = product_used_sql(product, portfolio, purchased_col, experimental=experimental)
        gauge_thresholds = ORIGINAL_PRODUCT_USAGE_THRESHOLDS if experimental else None
        stat_w = 4 if experimental and product != "ca" else (5 if experimental else 4)
        metric_h = 5
        panels.append(
            gauge_panel(
                f"{label} - Usage %",
                pct_sql,
                0,
                y,
                w=stat_w,
                h=metric_h,
                thresholds=gauge_thresholds,
            )
        )
        panels.append(
            stat_panel(
                f"{label} - Purchased",
                product_purchased_sql(purchased_col, portfolio, product=product, experimental=experimental),
                stat_w,
                y,
                w=stat_w,
                h=metric_h,
            )
        )
        panels.append(
            stat_panel(f"{label} - Used", used_sql, stat_w * 2, y, w=stat_w, h=metric_h)
        )
        if experimental and product != "ca":
            panels.append(
                stat_panel(
                    f"{label} - Exceeded",
                    product_exceeded_sql(product, portfolio, purchased_col, experimental=experimental),
                    stat_w * 3,
                    y,
                    w=3,
                    h=metric_h,
                )
            )
            panels.append(
                stat_panel(
                    f"{label} - Total Used",
                    product_total_used_sql(product, portfolio, purchased_col, experimental=experimental),
                    stat_w * 3 + 3,
                    y,
                    w=stat_w,
                    h=metric_h,
                )
            )
            avg_x, avg_w = stat_w * 4 + 3, 5
        else:
            avg_x, avg_w = stat_w * 3, stat_w
        panels.append(
            gauge_panel(
                f"{label} - Usage AVG",
                product_avg_usage_sql(product, purchased_col, portfolio, experimental=experimental),
                avg_x,
                y,
                w=avg_w,
                h=metric_h,
                thresholds=gauge_thresholds,
                description=(
                    "Average of monthly Utilization % across all months in the selected Time Range filter "
                    "(not the same as Avg (Last 3M) in the table below)."
                ),
            )
        )
        y += metric_h

    util_height = 16
    util_months = 24
    util_title = (
        f"{label} Monthly Utilization % by Customer"
        if use_portfolio_sql
        else f"{label} Monthly Utilization %"
    )
    panels.append(
        product_utilization_table_panel(
            util_title,
            product,
            purchased_col,
            portfolio=use_portfolio_sql,
            x=0,
            y=y,
            h=util_height,
            experimental=experimental,
            months_count=util_months,
            include_current_month=True,
        )
    )
    return panels, y + util_height


def objects_info_panel(y):
    sql = load_query("objects_info.sql", time_range_contract_col="")
    return {
        "type": "barchart",
        "title": "Objects info",
        "description": "Stacked monthly object counts from latest report per month. Legend shows last count per type.",
        "gridPos": {"h": 18, "w": 24, "x": 0, "y": y},
        "id": next_id(),
        "targets": [sql_target(sql, query_type="table", ref="A", time_columns=["time", "ts"])],
        "options": {
            "barRadius": 0,
            "barWidth": 0.97,
            "fullHighlight": False,
            "groupWidth": 0.7,
            "legend": {
                "calcs": ["last"],
                "displayMode": "list",
                "placement": "right",
                "showLegend": True,
            },
            "orientation": "auto",
            "showValue": "never",
            "stacking": "normal",
            "tooltip": {"mode": "single", "sort": "none"},
            "xField": "month",
            "xTickLabelRotation": 0,
            "xTickLabelSpacing": 0,
        },
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {
                    "axisBorderShow": False,
                    "axisCenteredZero": False,
                    "axisColorMode": "text",
                    "axisLabel": "",
                    "axisPlacement": "auto",
                    "fillOpacity": 80,
                    "gradientMode": "none",
                    "hideFrom": {"legend": False, "tooltip": False, "viz": False},
                    "lineWidth": 1,
                    "scaleDistribution": {"type": "linear"},
                    "thresholdsStyle": {"mode": "off"},
                },
                "mappings": [],
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "red", "value": 80},
                    ],
                },
            },
            "overrides": [
                {
                    "matcher": {"id": "byName", "options": "Purchased Limit"},
                    "properties": [{"id": "color", "value": {"fixedColor": "yellow", "mode": "fixed"}}],
                },
                {
                    "matcher": {"id": "byName", "options": "Certificate"},
                    "properties": [{"id": "color", "value": {"fixedColor": "blue", "mode": "fixed"}}],
                },
            ],
        },
        "datasource": DS,
    }


def objects_section(y, multi_account=False):
    panels = [row_panel("Objects Info", y)]
    y += 1
    if multi_account:
        panels.append(
            table_panel(
                "Objects Info by Customer",
                load_query("objects_info.sql", group_by_company=True),
                0,
                y,
                w=24,
                h=10,
            )
        )
        return panels, y + 10
    panels.append(objects_info_panel(y))
    return panels, y + 18


def gateway_section(y):
    panels = [row_panel("Gateway Infrastructure", y)]
    y += 1
    panels.append(
        stat_panel(
            "Active Clusters",
            load_query("gateway_stat_clusters.sql"),
            0,
            y,
            w=6,
            h=4,
            thresholds=GATEWAY_CLUSTER_COUNT_THRESHOLDS,
        )
    )
    panels.append(
        stat_panel(
            "Gateway Instances",
            load_query("gateway_stat_instances.sql"),
            6,
            y,
            w=6,
            h=4,
            thresholds=POSITIVE_COUNT_THRESHOLDS,
        )
    )
    panels.append(
        stat_panel(
            "Log Forwarders",
            load_query("gateway_stat_log_forwarders.sql"),
            12,
            y,
            w=6,
            h=4,
            thresholds=POSITIVE_COUNT_THRESHOLDS,
        )
    )
    panels.append(
        stat_panel(
            "Snapshot Date",
            load_query("gateway_stat_snapshot_date.sql"),
            18,
            y,
            w=6,
            h=4,
        )
    )
    y += 4
    cluster_overrides = [
        text_status_override("Status", GATEWAY_STATUS_COLORS),
        {
            "matcher": {"id": "byName", "options": "Instances"},
            "properties": [
                {"id": "custom.cellOptions", "value": {"type": "color-background", "mode": "basic"}},
                {"id": "custom.width", "value": 120},
                {"id": "thresholds", "value": POSITIVE_COUNT_THRESHOLDS},
                {"id": "color", "value": {"mode": "thresholds"}},
            ],
        },
        {
            "matcher": {"id": "byName", "options": "Access ID"},
            "properties": [{"id": "custom.width", "value": 300}],
        },
    ]
    panels.append(
        table_panel(
            "Gateway Clusters — Active Inventory",
            load_query("gateway_clusters_detail.sql"),
            0,
            y,
            w=14,
            h=11,
            overrides=cluster_overrides,
            description="Counts from latest ObjectsReport (report_objects). Access ID per cluster is not in the current SQLite schema.",
        )
    )
    panels.append(
        piechart_panel(
            "Log Forwarding — Type Mix",
            load_query("gateway_log_forwarding_types_pie.sql"),
            14,
            y,
            w=10,
            h=6,
            label_field="Type",
            value_field="Count",
        )
    )
    panels.append(
        table_panel(
            "Log Forwarders — Configuration",
            load_query("gateway_log_forwarding_detail.sql"),
            14,
            y + 6,
            w=10,
            h=5,
            description="From report_objects gateway_log_forwarding rows in the latest snapshot.",
        )
    )
    return panels, y + 11


def single_account_anomaly_panels(y, multi_account=False, experimental=True):
    panels = [row_panel("Technical Trends & Anomalies", y)]
    y += 1
    legacy = not experimental
    trend_overrides = [
        text_status_override("Trend Alert", TREND_ALERT_COLORS),
        pct_field_override("Change %", OBJECT_TREND_CHANGE_THRESHOLDS, unit="percent"),
    ]
    panels.append(
        table_panel(
            "Top Object Growth (Last 3 Months)",
            load_query("trend_top_object_growth.sql", group_by_company=multi_account, legacy=legacy),
            0,
            y,
            w=24,
            h=8,
            description="Top 5 object types by net growth from the start to the end of the last 3 completed calendar months.",
        )
    )
    y += 8
    panels.append(
        table_panel(
            "Objects Trend - All Growth & Reduction Indications",
            load_query("objects_trend.sql", group_by_company=multi_account, legacy=legacy),
            0,
            y,
            h=8,
            overrides=trend_overrides,
            description=(
                "Net change across the last 3 completed calendar months. "
                "Trend Alert definitions: "
                "New — Review = appeared in window (0 → N); "
                "Growth — Good = >10% increase; "
                "Stable Growth = >0 and ≤10% increase; "
                "Stable = no change; "
                "Stable Decline = <0 and ≥−10% decrease; "
                "Reduction — Review = >10% decrease; "
                "Stale — No Growth in 3 Months = flat across all 3 months."
            ),
        )
    )
    y += 8
    panels.append(
        table_panel(
            "New Use Cases — Secrets & Authentication (Adoption Signals)",
            load_query("trend_new_use_cases.sql", group_by_company=multi_account, legacy=legacy),
            0,
            y,
            h=10,
            description=(
                "One row per type: net change from the start to the end of the last 3 completed calendar months. "
                "Start → End shows the count window; Count is the end value (sortable)."
            ),
            overrides=[text_status_override("Adoption Signal", ADOPTION_SIGNAL_COLORS)],
            sort_by=("Count", True),
        )
    )
    return panels, y + 10


def best_practice_section(y, multi_account=False, experimental=True):
    panels = [row_panel("Best Practice — Secrets & Authentication", y)]
    y += 1
    legacy = not experimental

    practice_table_overrides = [
        pct_field_override("Static %", INVERSE_PCT_THRESHOLDS),
        pct_field_override("API Key %", INVERSE_PCT_THRESHOLDS),
        text_status_override("Recommendation", RECOMMENDATION_COLORS),
    ]

    if not multi_account:
        panels.append(
            piechart_panel(
                "Secret Type Mix",
                load_query("best_practice_secrets_mix_pie.sql", legacy=legacy),
                0,
                y,
                w=8,
                h=6,
                label_field="Secret Type",
                value_field="Count",
            )
        )
        panels.append(
            piechart_panel(
                "Authentication Method Mix",
                load_query("best_practice_auth_mix_pie.sql", legacy=legacy),
                8,
                y,
                w=16,
                h=6,
            )
        )
        y += 6

        if experimental:
            panels.append(
                bargauge_panel(
                    "Static Credentials vs Secretless Authentication",
                    load_query("best_practice_api_key_vs_preferred.sql"),
                    0,
                    y,
                    w=24,
                    h=5,
                    overrides=auth_method_mix_overrides(comparison=True),
                    description="Secretless means: CSP IAM, JWT, K8s",
                    comparison=True,
                )
            )
        else:
            panels.append(
                bargauge_panel(
                    "API Key vs Universal Identity",
                    load_query("best_practice_api_key_vs_ui.sql"),
                    0,
                    y,
                    w=12,
                    h=5,
                    overrides=auth_method_mix_overrides(),
                )
            )
            panels.append(
                bargauge_panel(
                    "API Key vs Cloud IAM",
                    load_query("best_practice_api_key_vs_cloud.sql"),
                    12,
                    y,
                    w=12,
                    h=5,
                    overrides=auth_method_mix_overrides(),
                )
            )
        y += 5

    panels.append(
        table_panel(
            "Secrets — Static vs Dynamic/Rotated",
            load_query("best_practice_secrets.sql", group_by_company=multi_account, legacy=legacy),
            0,
            y,
            w=12 if not multi_account else 24,
            h=8 if multi_account else 6,
            overrides=practice_table_overrides,
        )
    )
    if not multi_account:
        panels.append(
            table_panel(
                "Authentication — Recommended Methods",
                load_query("best_practice_authentication.sql", legacy=legacy),
                12,
                y,
                w=12,
                h=6,
                overrides=practice_table_overrides,
            )
        )
        y += 6
    else:
        panels.append(
            table_panel(
                "Authentication — Recommended Methods",
                load_query("best_practice_authentication.sql", group_by_company=True, legacy=legacy),
                0,
                y,
                w=24,
                h=8,
                overrides=practice_table_overrides,
            )
        )
        y += 8

    access_type_mom_overrides = [
        pct_field_override("Change", CHANGE_THRESHOLDS, unit="none"),
        {
            "matcher": {"id": "byName", "options": "End Total"},
            "properties": [
                {"id": "custom.hidden", "value": True},
            ],
        },
    ]
    panels.append(
        table_panel(
            "Access Type — Used Clients (Last 3 Months)",
            load_query("risk_access_type_mom.sql", group_by_company=multi_account, legacy=legacy),
            0,
            y,
            w=24,
            h=8,
            overrides=access_type_mom_overrides,
            description=(
                (
                    "Complete access-type inventory per customer: one row per auth method, "
                    if multi_account
                    else "Complete access-type inventory for the account: one row per auth method, "
                )
                + "totals aggregated across SM, SRA, and PWM. "
                + "Period is the last 3 completed calendar months (excludes the current incomplete month)."
            ),
            sort_by=("End Total", True),
        )
    )
    return panels, y + 8


def risk_section(y, group_by_company=False, experimental=True):
    panels = [row_panel("Risk Mitigation — SM, SRA, PWM", y)]
    y += 1
    legacy = not experimental
    risk_status_overrides = [
        text_status_override("Risk Status", RISK_STATUS_COLORS),
    ]
    alert_overrides = [
        text_status_override("Alert", ALERT_STATUS_COLORS),
        pct_field_override("Change", CHANGE_THRESHOLDS, unit="none"),
    ]
    access_type_overrides = [
        {
            "matcher": {"id": "byName", "options": "Exceeded Clients"},
            "properties": [
                {"id": "custom.cellOptions", "value": {"type": "color-background", "mode": "basic"}},
                {"id": "thresholds", "value": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "red", "value": 1},
                    ],
                }},
                {"id": "color", "value": {"mode": "thresholds"}},
            ],
        },
    ]
    panels.append(
        table_panel(
            "Access Type Breakdown",
            load_query("risk_access_type_breakdown.sql", group_by_company=group_by_company, legacy=legacy),
            0,
            y,
            h=8,
            overrides=access_type_overrides,
            description=(
                (
                    "One row per client access type per customer, totals aggregated across SM, SRA, and PWM. "
                    if group_by_company
                    else "One row per client access type, totals aggregated across SM, SRA, and PWM. "
                )
                + "Shows the last completed calendar month (excludes the current incomplete month)."
            ),
            sort_by=("Total Clients", True),
        )
    )
    y += 8
    panels.append(
        table_panel(
            "Last Full Month Status — Usage vs Purchased Limit",
            load_query("risk_current_status.sql", group_by_company=group_by_company, legacy=legacy),
            0,
            y,
            h=6,
            overrides=risk_status_overrides,
            description=(
                "Used = within purchased limit. Exceeded is separate. "
                "Total Clients including Exceeding = Used Clients + Exceeded."
            ),
        )
    )
    y += 6
    panels.append(
        table_panel(
            "Client Usage Change (Last 3 Months)",
            load_query("risk_usage_month_over_month.sql", group_by_company=group_by_company, legacy=legacy),
            0,
            y,
            h=6,
            overrides=alert_overrides,
            description=(
                "Used = within purchased limit. Total = Used + Exceeded. "
                "Change is based on Total over the 3-month window."
            ),
        )
    )
    y += 6
    panels.append(
        table_panel(
            "Repeated Exceeded Clients — Last Month Detail",
            load_query("risk_repeated_exceeded.sql", group_by_company=group_by_company, legacy=legacy),
            0,
            y,
            h=8,
            overrides=[text_status_override("Risk", RISK_STATUS_COLORS)],
        )
    )
    y += 8
    panels.append(
        table_panel(
            "Adoption Status — Contract Age & Usage",
            load_query("risk_under_adopted_contract.sql", group_by_company=group_by_company, legacy=legacy),
            0,
            y,
            h=6,
            overrides=risk_status_overrides,
            description=(
                "Used = within purchased limit (contract year cumulative). "
                "Exceeded is separate. Total = Used + Exceeded."
            ),
        )
    )
    y += 6
    if not experimental:
        panels.append(
            table_panel(
                "Usage Month over Month Status",
                load_query("risk_zero_usage_alert.sql", group_by_company=group_by_company, legacy=legacy),
                0,
                y,
                h=6,
                overrides=alert_overrides,
            )
        )
        y += 6
    return panels, y


def product_label_full(label):
    return {
        "SM": "Secrets Management",
        "CLM": "Certificate Lifecycle Management",
        "SRA": "Secure Remote Access",
        "PWM": "Password Management",
    }[label]


def portfolio_anomaly_panels(y):
    panels = [row_panel("Portfolio Anomalies", y)]
    y += 1

    under_adopted = """
SELECT c.name AS "Customer", c.account_id AS "Account ID",
  c.clients_sm AS "SM Purchased", r.clients_sm_total_amount AS "SM Used",
  ROUND(100.0 * r.clients_sm_total_amount / NULLIF(c.clients_sm, 0), 1) AS "SM Util %"
FROM companies c
JOIN reports r ON r.account_id = c.account_id AND r.report_type = 'clients_report'
WHERE r.report_date = (
  SELECT MAX(r2.report_date) FROM reports r2
  WHERE r2.account_id = c.account_id AND r2.report_type = 'clients_report'
)
  AND {company_match_expr('c.name')}
  AND {account_match_expr('c.account_id')}
  AND c.clients_sm > 0
  AND r.clients_sm_total_amount < c.clients_sm * 0.3
ORDER BY "SM Util %" ASC
"""
    panels.append(table_panel("Under-Adopted Accounts (SM < 30%)", under_adopted, 0, y, h=8))
    y += 8

    stale = """
SELECT c.name AS "Customer", c.account_id AS "Account ID",
  MAX(r.report_date) AS "Last Report",
  CAST(julianday('now') - julianday(MAX(r.report_date)) AS INTEGER) AS "Days Since Report"
FROM companies c
LEFT JOIN reports r ON r.account_id = c.account_id AND r.report_type = 'clients_report'
WHERE {company_match_expr('c.name')}
  AND {account_match_expr('c.account_id')}
GROUP BY c.account_id
HAVING "Days Since Report" > 35 OR "Last Report" IS NULL
ORDER BY "Days Since Report" DESC
"""
    panels.append(table_panel("Stale Reporting (>35 days)", stale, 0, y, h=8))
    return panels, y + 8

def templating_single(experimental=True):
    return {
        "list": [
            {
                "name": "company_name",
                "type": "query",
                "label": "Company Name",
                "datasource": DS,
                "query": "SELECT DISTINCT name AS __value, name AS __text FROM companies WHERE name IS NOT NULL ORDER BY name",
                "refresh": 1,
                "includeAll": False,
                "multi": False,
            },
            {
                "name": "account_id",
                "type": "query",
                "label": "Account ID",
                "datasource": DS,
                "query": "SELECT DISTINCT account_id AS __value, account_id AS __text FROM companies WHERE name = '$company_name' AND account_id IS NOT NULL ORDER BY account_id",
                "refresh": 2,
                "includeAll": experimental,
                **({"allValue": VAR_ALL_VALUE} if experimental else {}),
                "multi": False,
            },
            period_variable(experimental),
        ]
    }


def templating_multi_account(experimental=True):
    return {
        "list": [
            {
                "name": "company_name",
                "type": "query",
                "label": "Company Name",
                "datasource": DS,
                "query": "SELECT DISTINCT name AS __value, name AS __text FROM companies WHERE name IS NOT NULL ORDER BY name",
                "refresh": 1,
                "includeAll": True,
                "allValue": VAR_ALL_VALUE,
                "multi": True,
            },
            {
                "name": "account_id",
                "type": "custom",
                "label": "Account ID",
                "hide": 2,
                "query": "All",
                "options": [{"selected": True, "text": "All", "value": "All"}],
                "current": {"selected": True, "text": "All", "value": "All"},
                "includeAll": False,
                "multi": False,
            },
            period_variable(experimental),
        ]
    }


def templating_portfolio(experimental=True):
    t = templating_single(experimental=experimental)
    t["list"][0]["multi"] = True
    t["list"][0]["includeAll"] = True
    t["list"][0]["allValue"] = VAR_ALL_VALUE
    t["list"][1]["multi"] = True
    t["list"][1]["includeAll"] = True
    t["list"][1]["allValue"] = VAR_ALL_VALUE
    t["list"][1]["query"] = (
        "SELECT DISTINCT account_id AS __value, name || ' (' || account_id || ')' AS __text "
        "FROM companies WHERE account_id IS NOT NULL "
        f"AND ({COMPANY_ALL_CHECK} OR name IN (${{company_name:sqlstring}})) "
        "ORDER BY name, account_id"
    )
    return t


def build_dashboard(title, uid, portfolio=False, multi_account=False, experimental=True, test=False):
    reset_ids()
    panels = []
    y = 0
    use_portfolio_sql = portfolio or multi_account

    if not portfolio and not multi_account and experimental:
        header_panels, y = original_account_header_panels(y)
        panels.extend(header_panels)
    elif portfolio and not multi_account:
        detail_panels, y = account_details_panels(y, portfolio=True, experimental=experimental)
        panels.extend(detail_panels)

    for label, product, purchased_col in PRODUCTS:
        section, y = product_section(
            label,
            product,
            purchased_col,
            y,
            portfolio=use_portfolio_sql,
            multi_account=multi_account,
            experimental=experimental,
        )
        panels.extend(section)

    use_customer_tables = (multi_account or portfolio) and experimental
    obj_panels, y = objects_section(y, multi_account=use_customer_tables)
    panels.extend(obj_panels)

    if portfolio and not multi_account:
        legacy_panels, y = portfolio_anomaly_panels(y)
        panels.extend(legacy_panels)
        if experimental:
            trend, y = single_account_anomaly_panels(y, multi_account=True, experimental=experimental)
            panels.extend(trend)
            practice, y = best_practice_section(y, multi_account=True, experimental=experimental)
            panels.extend(practice)
            risk, y = risk_section(y, group_by_company=True, experimental=experimental)
            panels.extend(risk)
    else:
        trend, y = single_account_anomaly_panels(
            y, multi_account=multi_account, experimental=experimental
        )
        panels.extend(trend)
        practice, y = best_practice_section(y, multi_account=multi_account, experimental=experimental)
        panels.extend(practice)
        risk, y = risk_section(y, group_by_company=multi_account, experimental=experimental)
        panels.extend(risk)

    if multi_account:
        templating = templating_multi_account(experimental=experimental)
        tags = ["akeyless", "customer-success", "usage", "technical", "multi-account"]
        if test:
            tags.append("test")
    elif portfolio:
        templating = templating_portfolio(experimental=experimental)
        tags = ["akeyless", "customer-success", "usage", "technical", "portfolio"]
    else:
        templating = templating_single(experimental=experimental)
        tags = ["akeyless", "customer-success", "usage", "technical"]
        if test:
            tags.append("test")

    return {
        "annotations": {"list": []},
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "id": None,
        "links": [],
        "liveNow": False,
        "panels": panels,
        "refresh": "",
        "schemaVersion": 39,
        "style": "dark",
        "tags": tags,
        "templating": templating,
        "time": {"from": "now-12M", "to": "now"},
        "timepicker": {},
        "timezone": "browser",
        "title": title,
        "uid": uid,
        "version": 25,
        "weekStart": "",
    }


# Panels that must keep identical display settings (type, size, options, fieldConfig)
# across single- and multi-account dashboards. SQL/title may differ by design.
SHARED_PANEL_TITLES = (
    "Top Object Growth (Last 3 Months)",
    "Objects Trend - All Growth & Reduction Indications",
    "New Use Cases — Secrets & Authentication (Adoption Signals)",
    "Access Type — Used Clients (Last 3 Months)",
    "Access Type Breakdown",
    "Last Full Month Status — Usage vs Purchased Limit",
    "Client Usage Change (Last 3 Months)",
    "Repeated Exceeded Clients — Last Month Detail",
    "Adoption Status — Contract Age & Usage",
)

PRODUCT_UTILIZATION_PREFIXES = ("SM", "CLM", "SRA", "PWM")

PANEL_COMPARE_IGNORE_KEYS = frozenset({"id", "targets", "title", "description"})
PANEL_COMPARE_GRIDPOS_IGNORE = frozenset({"x", "y"})


def _normalize_panel_for_compare(panel):
    """Strip panel fields that are expected to differ between single/multi dashboards."""
    normalized = deepcopy(panel)
    for key in PANEL_COMPARE_IGNORE_KEYS:
        normalized.pop(key, None)
    if "gridPos" in normalized:
        normalized["gridPos"] = {
            k: v for k, v in normalized["gridPos"].items() if k not in PANEL_COMPARE_GRIDPOS_IGNORE
        }
    return normalized


def _find_panel_by_title(panels, title):
    for panel in panels:
        if panel.get("title") == title:
            return panel
    return None


def _find_utilization_panel(panels, product_prefix):
    needle = f"{product_prefix} Monthly Utilization"
    matches = [p for p in panels if needle in p.get("title", "")]
    return matches[0] if len(matches) == 1 else None


def validate_single_multi_alignment(single_dashboard, multi_dashboard):
    """Fail generation when shared panels diverge in display settings."""
    issues = []
    single_panels = single_dashboard["panels"]
    multi_panels = multi_dashboard["panels"]

    for title in SHARED_PANEL_TITLES:
        single_panel = _find_panel_by_title(single_panels, title)
        multi_panel = _find_panel_by_title(multi_panels, title)
        if single_panel is None:
            issues.append(f"Missing shared panel on single-account dashboard: {title}")
            continue
        if multi_panel is None:
            issues.append(f"Missing shared panel on multi-account dashboard: {title}")
            continue
        single_norm = _normalize_panel_for_compare(single_panel)
        multi_norm = _normalize_panel_for_compare(multi_panel)
        if single_norm != multi_norm:
            issues.append(
                f"Display settings diverged for shared panel '{title}'. "
                "Update shared builders in generate_dashboards.py (not one JSON file only)."
            )

    for prefix in PRODUCT_UTILIZATION_PREFIXES:
        single_panel = _find_utilization_panel(single_panels, prefix)
        multi_panel = _find_utilization_panel(multi_panels, prefix)
        if single_panel is None or multi_panel is None:
            issues.append(f"Missing {prefix} Monthly Utilization panel on one dashboard")
            continue
        single_norm = _normalize_panel_for_compare(single_panel)
        multi_norm = _normalize_panel_for_compare(multi_panel)
        if single_norm != multi_norm:
            issues.append(
                f"Display settings diverged for {prefix} Monthly Utilization. "
                "Keep product_section() / product_utilization_table_panel() shared."
            )

    return issues


def main():
    prod_single = build_dashboard(
        "Akeyless CS — Account Technical Dashboard",
        "akeyless-cs-account-adoption",
        portfolio=False,
        experimental=True,
    )
    prod_multi = build_dashboard(
        "Akeyless CS — Multi-Account Technical Dashboard",
        "akeyless-cs-multi-account",
        multi_account=True,
        experimental=True,
    )
    prod_portfolio = build_dashboard(
        "Akeyless CS — Portfolio Anomalies Dashboard",
        "akeyless-cs-portfolio-anomalies",
        portfolio=True,
        experimental=False,
    )
    test_single = build_dashboard(
        "Akeyless CS — Account Technical Dashboard (TEST)",
        "akeyless-cs-test-single-account",
        portfolio=False,
        experimental=True,
        test=True,
    )
    test_multi = build_dashboard(
        "Akeyless CS — Multi-Account Technical Dashboard (TEST)",
        "akeyless-cs-test-multiple-accounts",
        multi_account=True,
        experimental=True,
        test=True,
    )

    paths = {
        OUT_DIR / "dashboard-single-account.json": prod_single,
        OUT_DIR / "dashboard-multi-account.json": prod_multi,
        OUT_DIR / "dashboard-portfolio-anomalies.json": prod_portfolio,
        OUT_DIR / "test-single-account.json": test_single,
        OUT_DIR / "test-multiple-accounts.json": test_multi,
    }
    for path, dashboard in paths.items():
        path.write_text(json.dumps(dashboard, indent=2))
        print(f"Wrote {path} ({len(dashboard['panels'])} panels)")

    alignment_issues = validate_single_multi_alignment(prod_single, prod_multi)
    if alignment_issues:
        print("\nDashboard alignment check FAILED:")
        for issue in alignment_issues:
            print(f"  - {issue}")
        raise SystemExit(1)
    print("Dashboard alignment check passed (single-account vs multi-account).")


if __name__ == "__main__":
    main()
