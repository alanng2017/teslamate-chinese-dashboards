#!/usr/bin/env bash
# dashboard JSON 静态 lint 门：把本项目踩过的真实坑变成可执行检查。
# 扫描范围：grafana/dashboards/zh-cn/*.json 和 grafana/dashboards/internal/*.json 全部
# （历史教训：v1.8.0 大审计只扫了 zh-cn 45 个，internal/ 3 个被漏审，#31 用户报的
#  中文面板就在 internal/ 里 grep 不到——绝不能只扫 zh-cn）。
#
# 跑：bash scripts/check-dashboard-lint.sh
# 退出码：0 = 全绿；1 = 有命中（打印 文件 :: 面板id/变量名 :: 规则字母 :: 摘要片段）
#
# 规则清单（字母对应下面 WHITELIST 条目的 rule）：
#   0 JSON 合法性             — json.load 失败即报错
#   a 裸点平均当均速           — 代码 token 含 AVG(speed)/AVG(p.speed)，包括冗余括号；
#                                分桶内均值仅在同一 target 确有 GROUP BY speed_bin 时放行。
#   b SQL 字符串字面量含 --    — Grafana 13.0.1 postgres 数据源会误剥字符串里的 --；
#                                检查单引号/E 字符串/dollar-quote 的字面量内容。
#   c 模板变量查询用 $__timezone — 模板变量查询中会解析成字面量 browser。
#   d timezone('$__timezone', X) 且 X≠NOW() — TeslaMate 朴素 UTC 列不能直接转；
#                                仅按白名单表达式放行 timezone('UTC', …) 或同一 SQL 中
#                                三参数 date_trunc(..., timezone('UTC', …), '$__timezone')
#                                产生的别名。
#   e 禁用自动换算单位         — lengthkm/lengthmi/short/kwatth；历史 drill-down 例外
#                                按 defaults 或具体 override matcher + value 精确放行。
#   f FROM settings WHERE id = $car_id — settings 是单行全局表；同时识别 schema 和
#                                双引号限定（public.settings / "settings"）。
#   g '${payload.X}' 裸强转     — 未填表单会产生 'undefined'；同时识别 ::TYPE 与
#                                CAST(expr AS TYPE)，TYPE 覆盖常用 PostgreSQL 数值类型。
#   h 老式 regex 抽 text/value — Grafana 9+/13 不再跨 /g 匹配拼接命名捕获组。
#   i 写表单无二次确认         — volkovlabs-form-panel 写操作必须 confirm=true。
#   j 用户可见文本汉化完整性   — title/displayName/变量 label/description/row 标题须含 CJK，
#                                或整串属于单位、术语、品牌、占位符、数字/符号白名单；
#                                只验证“至少一个 CJK”，不判断中英混排文本是否已完整汉化。
#   k 基线比较 override 孤儿   — table/stat 的 byName matcher 不在同面板顶层 SELECT AS 别名中；
#                                存量由精确多重集基线豁免，新增或过期基线均阻断。
#   l 自研函数存在性           — 形似项目自研的调用必须由 sql/install-*.sql 定义。
#   m dashboard 跳转 UID       — panel link/dataLink 中 /d/<uid> 必须指向仓内 dashboard。
#   n [报告档] timeseries 查询格式 — timeseries target 使用 format=table 时提示；被同面板
#                                configRefId 引用的配置帧明确豁免并打印说明。
#   o 柱状图趋势线             — drawStyle=bars 不得挂 regression/trendline transformation。
#   p 秒数/取模规范             — 禁止代码 token 中的 mod(...) 与 DATE_PART('epoch', ...)。
#   q [报告档] 可空列直等      — geofence_id =（排除 JOIN ON）可能破坏 NULL 全局语义。
#   r [报告档] 朴素 UTC 列     — NOW() - interval 邻域中的 date/start_date/end_date 应显式 UTC。
#   s 老变量语法               — rawSql 或模板变量内容不得包含 [[...]]。
#   t panel id 唯一性          — 同一 dashboard 内含 row 子面板的 panel id 不得重复。
#   u SQL target 数据源        — rawSql target 只允许 TeslaMate、继承值或模板变量 datasource。
#
# a/d/f/g/l/p/q/r 共用一次 PostgreSQL-lite 词法扫描后的代码 token 流（注释已剔除，字符串保留为
# 有类型 token）；b 只检查同一扫描产出的字符串字面量内容。白名单不是 panel 级开关：
# 每条都带可校验条件；本次扫描未命中的条目视为过期白名单并直接失败。

set -e
cd "$(dirname "$0")/.."

python3 - "$@" <<'PYEOF'
import glob
import hashlib
import json
import os
import re
import sys
import tempfile
from collections import Counter, namedtuple
from urllib.parse import urlsplit


_DRILLDOWN = (
    "单次会话/单车详情类有界小值；v1.6.8 已决定保留上游单位写法"
)


def entry(file_rel, subject, rule, condition, reason):
    return {
        'file': file_rel,
        'subject': subject,
        'rule': rule,
        'condition': condition,
        'reason': reason,
    }


# 白名单条目必须描述“哪一次命中为何允许”，而不是给整个 panel 关闭规则。
WHITELIST = [
    entry(
        'grafana/dashboards/zh-cn/SpeedRates.json', 2, 'a',
        {'kind': 'group_by_speed_bin', 'target_refs': ('A',)},
        "target A 的 AVG(speed) 与 GROUP BY speed_bin 同处一个 target，是桶内均值",
    ),

    entry(
        'grafana/dashboards/zh-cn/battery-health.json', 28, 'd',
        {'kind': 'timezone_utc', 'target_refs': ('预计续航', '中位数')},
        "X 必须精确匹配 timezone('UTC', …)",
    ),
    entry(
        'grafana/dashboards/zh-cn/charging-stats.json', 29, 'd',
        {'kind': 'timezone_utc', 'target_refs': ('A',)},
        "X 必须精确匹配 timezone('UTC', …)",
    ),
    entry(
        'grafana/dashboards/zh-cn/sentry-drain.json', 9, 'd',
        {'kind': 'timezone_utc', 'target_refs': ('A',)},
        "X 必须精确匹配 timezone('UTC', …)",
    ),
    entry(
        'grafana/dashboards/zh-cn/statistics.json', 2, 'd',
        {'kind': 'date_trunc_alias', 'target_refs': ('A', 'B', 'C', 'D')},
        "X 必须是同一 target 内三参数 date_trunc(..., timezone('UTC', …), "
        "'$__timezone') 的别名",
    ),
]


# (文件, panel, scope, matcher id, matcher options, unit, 理由)
# scope=defaults 时 matcher 两项必须为 None；override 条目按 matcher+value 精确匹配。
_E_WHITELIST = [
    ('grafana/dashboards/internal/charge-details.json', 2, 'override', 'byRegexp', '.*_km$', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/internal/charge-details.json', 2, 'override', 'byRegexp', '.*_mi$', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/internal/charge-details.json', 8, 'defaults', None, None, 'kwatth', _DRILLDOWN),
    ('grafana/dashboards/internal/charge-details.json', 14, 'override', 'byRegexp', '/.*_km/', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/internal/charge-details.json', 14, 'override', 'byRegexp', '/.*_mi/', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/internal/drive-details.json', 6, 'defaults', None, None, 'short', _DRILLDOWN),
    ('grafana/dashboards/internal/drive-details.json', 10, 'override', 'byName', 'km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/internal/drive-details.json', 10, 'override', 'byName', 'mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/internal/drive-details.json', 12, 'defaults', None, None, 'kwatth', _DRILLDOWN),
    ('grafana/dashboards/internal/drive-details.json', 32, 'defaults', None, None, 'short', _DRILLDOWN),
    ('grafana/dashboards/internal/drive-details.json', 40, 'defaults', None, None, 'kwatth', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentDriveView.json', 14, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentDriveView.json', 14, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 69, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 69, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 70, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 70, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/TrackingDrives.json', 12, 'override', 'byName', 'km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/TrackingDrives.json', 12, 'override', 'byName', 'mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/TrackingDrives.json', 16, 'defaults', None, None, 'kwatth', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/charges.json', 6, 'override', 'byName', 'range_added_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/charges.json', 6, 'override', 'byName', 'range_added_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/drive-stats.json', 8, 'override', 'byName', 'distance_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/drive-stats.json', 26, 'override', 'byName', 'distance_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/overview.json', 25, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/overview.json', 25, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/trip.json', 36, 'override', 'byName', 'range_added_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/trip.json', 36, 'override', 'byName', 'range_added_mi', 'lengthmi', _DRILLDOWN),
]

for file_rel, panel_id, scope, matcher_id, matcher_options, unit, reason in _E_WHITELIST:
    WHITELIST.append(entry(
        file_rel, panel_id, 'e',
        {
            'kind': 'unit',
            'scope': scope,
            'matcher_id': matcher_id,
            'matcher_options': matcher_options,
            'value': unit,
        },
        reason,
    ))


BANNED_UNITS = {'lengthkm', 'lengthmi', 'short', 'kwatth'}
NUMERIC_TYPES = {
    'int', 'integer', 'bigint', 'smallint', 'numeric', 'decimal', 'real', 'float',
}
DASHBOARD_GLOBS = [
    'grafana/dashboards/zh-cn/*.json',
    'grafana/dashboards/internal/*.json',
]
SQL_INSTALL_GLOB = 'sql/install-*.sql'
K_BASELINE_PATH = 'scripts/dashboard-lint-baseline.json'
K_BASELINE_VERSION = 1
REPORT_RULES = {'n', 'q', 'r'}

# j 的“整串”通用白名单。这里只放跨 dashboard 稳定成立的类别；具体历史例外仍进入
# WHITELIST，并继续受“本次未命中即过期”的约束。
VISIBLE_TEXT_EXACT_ALLOWLIST = {
    # 单位：Grafana 有些字段只显示括号中的单位，语义仍完整。
    'km', 'km/h', 'wh/km', 'kwh', 'kwh/km', '%', 'v', 'a', 'kw', 'min', 'h', '(km)',
    # 领域/技术术语。
    'soc', 'vin', 'ac', 'dc', 'lfp', 'api', 'ip', 'url', 'ota', 'tpms',
    'autopilot', 'fsd',
    # 品牌/专名：不应机械翻译。
    'tesla', 'teslamate', 'grafana', 'openstreetmap', 'google maps', '高德地图',
}
# 设计取舍：j 只把“至少出现一个 CJK 字符”当作已汉化的低成本信号；因此像
# “Battery Health中”这种中英混排会通过。完整翻译质量留给人工审校，避免静态规则误伤专名。
CJK_RE = re.compile(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]')
GRAFANA_PLACEHOLDER_RE = re.compile(
    r'^(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^{}]+\}|\{\{[^{}]+\}\}|\[\[[^\[\]]+\]\])$'
)
REGEX_PLACEHOLDER_RE = re.compile(r'^/(?:\\.|[^/])+/[A-Za-z]*$')
CUSTOM_FUNCTION_FAMILY_RE = re.compile(
    r'^(?:convert_.*|.*_for_map|effective_.*|apply_.*|tou_.*|_tou_.*|audit_.*|'
    r'backfill_.*|lookup_.*|compute_.*|is_outside_.*|set_.*|list_.*|dedup_.*|'
    r'trigger_.*|uninstall_.*|wgs84_to_.*)$', re.I
)
# 与上述自研命名族碰撞的 PostgreSQL 内置函数必须放行，避免 l 把数据库标准能力误报。
POSTGRES_BUILTIN_FUNCTIONS = {
    'convert_from', 'convert_to', 'is_normalized',
    'set_bit', 'set_byte', 'set_config', 'set_masklen',
}
DASHBOARD_PATH_RE = re.compile(r'(?:^|/)d/([A-Za-z0-9_-]+)(?=/|$)')
NAIVE_DATE_COLUMNS = {'date', 'start_date', 'end_date'}

Token = namedtuple('Token', 'kind value start end')
SqlContext = namedtuple('SqlContext', 'sql target_ref target_path')
PAYLOAD_LITERAL_RE = re.compile(r'^\$\{payload\.[^}]+\}$', re.I)
DOLLAR_TAG_RE = re.compile(r'\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$')


def tokenize_sql(sql):
    """一次 PostgreSQL-lite 扫描：返回去注释的代码 token 流和字符串字面量列表。

    支持标准/E 单引号字符串、dollar-quote、双引号标识符、-- 注释和可嵌套块注释。
    字符串在代码流中保留为有类型 token，供 cast 结构检查；b 使用单独的内容列表。
    """
    tokens = []
    literals = []
    i = 0
    n = len(sql)

    def scan_single_quote(quote_pos, escape_backslash, token_start):
        j = quote_pos + 1
        buf = []
        while j < n:
            if sql[j] == "'":
                if j + 1 < n and sql[j + 1] == "'":
                    buf.append("'")
                    j += 2
                    continue
                return ''.join(buf), j + 1
            if escape_backslash and sql[j] == '\\' and j + 1 < n:
                buf.extend((sql[j], sql[j + 1]))
                j += 2
                continue
            buf.append(sql[j])
            j += 1
        return ''.join(buf), n

    while i < n:
        c = sql[i]

        if c.isspace():
            i += 1
            continue

        if sql.startswith('--', i):
            newline = sql.find('\n', i + 2)
            i = n if newline == -1 else newline + 1
            continue

        if sql.startswith('/*', i):
            depth = 1
            i += 2
            while i < n and depth:
                if sql.startswith('/*', i):
                    depth += 1
                    i += 2
                elif sql.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue

        if c in 'Ee' and i + 1 < n and sql[i + 1] == "'" and (
            i == 0 or not (sql[i - 1].isalnum() or sql[i - 1] in '_$')
        ):
            value, end = scan_single_quote(i + 1, True, i)
            tokens.append(Token('string', value, i, end))
            literals.append(value)
            i = end
            continue

        if c == "'":
            value, end = scan_single_quote(i, False, i)
            tokens.append(Token('string', value, i, end))
            literals.append(value)
            i = end
            continue

        if c == '$':
            tag_match = DOLLAR_TAG_RE.match(sql, i)
            if tag_match:
                tag = tag_match.group(0)
                content_start = tag_match.end()
                close = sql.find(tag, content_start)
                end = n if close == -1 else close + len(tag)
                value = sql[content_start:] if close == -1 else sql[content_start:close]
                tokens.append(Token('string', value, i, end))
                literals.append(value)
                i = end
                continue
            if i + 1 < n and sql[i + 1] == '{':
                close = sql.find('}', i + 2)
                end = n if close == -1 else close + 1
                tokens.append(Token('variable', sql[i:end], i, end))
                i = end
                continue
            m = re.match(r'\$[A-Za-z_][A-Za-z0-9_]*', sql[i:])
            if m:
                end = i + len(m.group(0))
                tokens.append(Token('variable', m.group(0), i, end))
                i = end
                continue

        if c == '"':
            j = i + 1
            buf = []
            while j < n:
                if sql[j] == '"':
                    if j + 1 < n and sql[j + 1] == '"':
                        buf.append('"')
                        j += 2
                        continue
                    j += 1
                    break
                buf.append(sql[j])
                j += 1
            tokens.append(Token('quoted_identifier', ''.join(buf), i, j))
            i = j
            continue

        if c.isalpha() or c == '_' or ord(c) >= 128:
            j = i + 1
            while j < n:
                # Grafana 的 ${var} 可出现在未加引号的 SQL 标识符中，替换后才交给 PostgreSQL。
                if sql.startswith('${', j):
                    close = sql.find('}', j + 2)
                    if close != -1:
                        j = close + 1
                        continue
                if sql[j].isalnum() or sql[j] in '_$' or ord(sql[j]) >= 128:
                    j += 1
                    continue
                break
            tokens.append(Token('identifier', sql[i:j], i, j))
            i = j
            continue

        if c.isdigit():
            j = i + 1
            while j < n and (sql[j].isalnum() or sql[j] in '._'):
                j += 1
            tokens.append(Token('number', sql[i:j], i, j))
            i = j
            continue

        operator = next((op for op in ('::', '<=', '>=', '<>', '!=', '||', '->>') if sql.startswith(op, i)), None)
        if operator:
            tokens.append(Token('symbol', operator, i, i + len(operator)))
            i += len(operator)
            continue

        tokens.append(Token('symbol', c, i, i + 1))
        i += 1

    return tokens, literals


def identifier_value(token):
    if token.kind in ('identifier', 'quoted_identifier'):
        return token.value.lower()
    return None


def token_is(token, value):
    ident = identifier_value(token)
    return ident == value.lower() if ident is not None else token.value.lower() == value.lower()


def matching_paren(tokens, open_index):
    depth = 0
    for index in range(open_index, len(tokens)):
        if tokens[index].value == '(':
            depth += 1
        elif tokens[index].value == ')':
            depth -= 1
            if depth == 0:
                return index
    return None


def strip_outer_parens(tokens):
    result = list(tokens)
    while len(result) >= 2 and result[0].value == '(':
        close = matching_paren(result, 0)
        if close != len(result) - 1:
            break
        result = result[1:-1]
    return result


def split_top_level_tokens(tokens, separator=','):
    parts = []
    start = 0
    depth = 0
    for index, token in enumerate(tokens):
        if token.value == '(':
            depth += 1
        elif token.value == ')':
            depth -= 1
        elif depth == 0 and token.value.lower() == separator.lower():
            parts.append(tokens[start:index])
            start = index + 1
    parts.append(tokens[start:])
    return parts


def find_function_calls(tokens, name):
    """返回 (参数 token, 函数名 index, 右括号 index)，包含嵌套调用。"""
    calls = []
    for index in range(len(tokens) - 1):
        if identifier_value(tokens[index]) != name.lower() or tokens[index + 1].value != '(':
            continue
        close = matching_paren(tokens, index + 1)
        if close is not None:
            calls.append((tokens[index + 2:close], index, close))
    return calls


def function_call_names(tokens):
    """复用 token 流提取所有调用名；SQL 关键字即使形似调用，也过不了 l 的命名模式。"""
    return {
        identifier_value(tokens[index])
        for index in range(len(tokens) - 1)
        if identifier_value(tokens[index]) is not None and tokens[index + 1].value == '('
    }


def installed_function_names():
    """从 install SQL 的 CREATE [OR REPLACE] FUNCTION 自动提取项目函数名。"""
    names = set()
    for path in sorted(glob.glob(SQL_INSTALL_GLOB)):
        with open(path, encoding='utf-8') as handle:
            tokens, _ = tokenize_sql(handle.read())
        index = 0
        while index < len(tokens):
            if identifier_value(tokens[index]) != 'create':
                index += 1
                continue
            cursor = index + 1
            if cursor + 1 < len(tokens) and identifier_value(tokens[cursor]) == 'or' and identifier_value(tokens[cursor + 1]) == 'replace':
                cursor += 2
            if cursor >= len(tokens) or identifier_value(tokens[cursor]) != 'function':
                index += 1
                continue
            cursor += 1
            parts = []
            while cursor < len(tokens):
                ident = identifier_value(tokens[cursor])
                if ident is None:
                    break
                parts.append(ident)
                if cursor + 1 >= len(tokens) or tokens[cursor + 1].value != '.':
                    break
                cursor += 2
            if parts:
                names.add(parts[-1])
            index = cursor + 1
    return names


def derived_custom_function_prefixes(function_names):
    """从 install SQL 已定义函数自动派生首段命名族前缀，显式族清单作为稳定下限。"""
    prefixes = set()
    for name in function_names:
        match = re.match(r'^_?[a-z0-9]+_', name, re.I)
        if match:
            prefixes.add(match.group(0).lower())
    return prefixes


def looks_like_custom_function(name, derived_prefixes):
    lowered = name.lower()
    if lowered in POSTGRES_BUILTIN_FUNCTIONS:
        return False
    return (
        CUSTOM_FUNCTION_FAMILY_RE.fullmatch(lowered) is not None
        or any(lowered.startswith(prefix) for prefix in derived_prefixes)
    )


def exact_function_args(tokens, name):
    expr = strip_outer_parens(tokens)
    calls = find_function_calls(expr, name)
    if not calls:
        return None
    args, start, close = calls[0]
    if start == 0 and close == len(expr) - 1:
        return split_top_level_tokens(args)
    return None


def is_speed_expression(tokens):
    expr = strip_outer_parens(tokens)
    if len(expr) == 1:
        return identifier_value(expr[0]) == 'speed'
    if len(expr) == 3 and expr[1].value == '.':
        return identifier_value(expr[0]) is not None and identifier_value(expr[2]) == 'speed'
    return False


def avg_speed_calls(tokens):
    matches = []
    for args, start, close in find_function_calls(tokens, 'avg'):
        parts = split_top_level_tokens(args)
        if len(parts) == 1 and is_speed_expression(parts[0]):
            matches.append((start, close))
    return matches


def has_group_by_speed_bin(tokens):
    for index in range(len(tokens) - 2):
        if identifier_value(tokens[index]) != 'group' or identifier_value(tokens[index + 1]) != 'by':
            continue
        depth = 0
        for token in tokens[index + 2:]:
            if token.value == '(':
                depth += 1
            elif token.value == ')':
                depth -= 1
            elif depth == 0 and identifier_value(token) in {'having', 'order', 'limit', 'union'}:
                break
            elif identifier_value(token) == 'speed_bin':
                return True
    return False


def is_now_call(tokens):
    return exact_function_args(tokens, 'now') == [[]]


def string_arg_equals(tokens, expected):
    expr = strip_outer_parens(tokens)
    return len(expr) == 1 and expr[0].kind == 'string' and expr[0].value.lower() == expected.lower()


def is_timezone_utc_expression(tokens):
    args = exact_function_args(tokens, 'timezone')
    return args is not None and len(args) == 2 and string_arg_equals(args[0], 'UTC')


def date_trunc_aliases(tokens):
    aliases = set()
    for args, _, close in find_function_calls(tokens, 'date_trunc'):
        parts = split_top_level_tokens(args)
        if len(parts) != 3:
            continue
        if not is_timezone_utc_expression(parts[1]) or not string_arg_equals(parts[2], '$__timezone'):
            continue
        alias_index = close + 1
        if alias_index < len(tokens) and identifier_value(tokens[alias_index]) == 'as':
            alias_index += 1
        if alias_index < len(tokens) and identifier_value(tokens[alias_index]) is not None:
            aliases.add(identifier_value(tokens[alias_index]))
    return aliases


def is_date_trunc_alias_expression(arg_tokens, all_tokens):
    expr = strip_outer_parens(arg_tokens)
    return len(expr) == 1 and identifier_value(expr[0]) in date_trunc_aliases(all_tokens)


def settings_car_id_matches(tokens):
    matches = []
    for index, token in enumerate(tokens):
        if identifier_value(token) != 'from':
            continue
        cursor = index + 1
        names = []
        if cursor >= len(tokens) or identifier_value(tokens[cursor]) is None:
            continue
        names.append(identifier_value(tokens[cursor]))
        cursor += 1
        while cursor + 1 < len(tokens) and tokens[cursor].value == '.' and identifier_value(tokens[cursor + 1]) is not None:
            names.append(identifier_value(tokens[cursor + 1]))
            cursor += 2
        if names[-1] != 'settings':
            continue
        end = next((j for j in range(cursor, len(tokens)) if tokens[j].value == ';'), len(tokens))
        where = next((j for j in range(cursor, end) if identifier_value(tokens[j]) == 'where'), None)
        if where is None:
            continue
        for j in range(where + 1, end - 2):
            if identifier_value(tokens[j]) != 'id':
                continue
            if tokens[j + 1].value == '=' and tokens[j + 2].kind == 'variable' and tokens[j + 2].value.lower() == '$car_id':
                matches.append((index, j + 2))
    return matches


def payload_literal(tokens):
    expr = strip_outer_parens(tokens)
    return len(expr) == 1 and expr[0].kind == 'string' and PAYLOAD_LITERAL_RE.match(expr[0].value)


def numeric_type(tokens):
    expr = strip_outer_parens(tokens)
    if not expr or identifier_value(expr[0]) is None:
        return None
    first = identifier_value(expr[0])
    if first == 'double' and len(expr) > 1 and identifier_value(expr[1]) == 'precision':
        return 'double precision'
    if first in NUMERIC_TYPES:
        return first
    return None


def payload_cast_matches(tokens):
    matches = []
    for index, token in enumerate(tokens):
        if token.kind != 'string' or not PAYLOAD_LITERAL_RE.match(token.value):
            continue
        if index + 2 < len(tokens) and tokens[index + 1].value == '::' and numeric_type(tokens[index + 2:]):
            matches.append((index, index + 2))

    for args, start, close in find_function_calls(tokens, 'cast'):
        depth = 0
        as_index = None
        for index, token in enumerate(args):
            if token.value == '(':
                depth += 1
            elif token.value == ')':
                depth -= 1
            elif depth == 0 and identifier_value(token) == 'as':
                as_index = index
        if as_index is None:
            continue
        if payload_literal(args[:as_index]) and numeric_type(args[as_index + 1:]):
            matches.append((start, close))
    return matches


def top_level_select_fields(tokens):
    """启发式提取顶层 SELECT 输出名；返回 (确定字段名, 是否含无法展开的 *)。"""
    fields = set()
    has_wildcard = False
    depth = 0
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.value == '(':
            depth += 1
            index += 1
            continue
        if token.value == ')':
            depth -= 1
            index += 1
            continue
        if depth != 0 or identifier_value(token) != 'select':
            index += 1
            continue

        select_depth = depth
        end = index + 1
        local_depth = select_depth
        while end < len(tokens):
            current = tokens[end]
            if current.value == '(':
                local_depth += 1
            elif current.value == ')':
                local_depth -= 1
            elif local_depth == select_depth and identifier_value(current) == 'from':
                break
            end += 1

        for expression in split_top_level_tokens(tokens[index + 1:end]):
            expression = [token for token in expression if identifier_value(token) not in {'distinct', 'all'}]
            expr_depth = 0
            explicit_alias = None
            for offset, current in enumerate(expression[:-1]):
                if current.value == '(':
                    expr_depth += 1
                elif current.value == ')':
                    expr_depth -= 1
                elif expr_depth == 0 and identifier_value(current) == 'as':
                    alias_token = expression[offset + 1]
                    if alias_token.kind == 'quoted_identifier':
                        explicit_alias = alias_token.value
                    elif alias_token.kind == 'identifier':
                        explicit_alias = alias_token.value.lower()
            if explicit_alias is not None:
                fields.add(explicit_alias)
                continue

            expr = strip_outer_parens(expression)
            if expr and expr[-1].value == '*' and (
                len(expr) == 1 or (len(expr) == 3 and expr[1].value == '.')
            ):
                has_wildcard = True
                continue
            if len(expr) == 1 and expr[0].kind in {'identifier', 'quoted_identifier'}:
                fields.add(expr[0].value if expr[0].kind == 'quoted_identifier' else expr[0].value.lower())
                continue
            if (
                len(expr) == 3 and expr[1].value == '.'
                and expr[0].kind in {'identifier', 'quoted_identifier'}
                and expr[2].kind in {'identifier', 'quoted_identifier'}
            ):
                fields.add(expr[2].value if expr[2].kind == 'quoted_identifier' else expr[2].value.lower())
        index = end
    return fields, has_wildcard


def mod_or_date_part_matches(tokens):
    matches = []
    for _, start, close in find_function_calls(tokens, 'mod'):
        matches.append((start, close, 'mod(...)'))
    for args, start, close in find_function_calls(tokens, 'date_part'):
        parts = split_top_level_tokens(args)
        if parts and string_arg_equals(parts[0], 'epoch'):
            matches.append((start, close, "DATE_PART('epoch', ...)"))
    return matches


def has_legacy_variable_code_token(tokens):
    """只识别代码流中相邻的 [[；注释已被 tokenizer 丢弃，字符串保留为单个 token。"""
    return any(
        left.value == '[' and right.value == '[' and left.end == right.start
        for left, right in zip(tokens, tokens[1:])
    )


def token_depths(tokens):
    depths = []
    depth = 0
    for token in tokens:
        depths.append(depth)
        if token.value == '(':
            depth += 1
        elif token.value == ')':
            depth = max(0, depth - 1)
    return depths


def in_join_on_context(tokens, index, depths):
    depth = depths[index]
    saw_on = False
    for cursor in range(index - 1, -1, -1):
        # ON (a.geofence_id = b.geofence_id) 的 ON 位于更浅一层；只跳过更深层 token。
        if depths[cursor] > depth:
            continue
        ident = identifier_value(tokens[cursor])
        if ident in {'where', 'having', 'group', 'order', 'union', 'limit'} or tokens[cursor].value == ';':
            return False
        if ident == 'on':
            saw_on = True
            continue
        if saw_on and ident == 'join':
            return True
    return False


def geofence_equality_matches(tokens):
    depths = token_depths(tokens)
    matches = []

    def is_geofence_reference(expression):
        expression = strip_outer_parens(expression)
        if len(expression) == 1:
            return identifier_value(expression[0]) == 'geofence_id'
        return (
            len(expression) == 3
            and identifier_value(expression[0]) is not None
            and expression[1].value == '.'
            and identifier_value(expression[2]) == 'geofence_id'
        )

    def operand_before(equals_index):
        for start in range(equals_index - 1, max(-1, equals_index - 8), -1):
            if is_geofence_reference(tokens[start:equals_index]):
                return start, equals_index - 1
        return None

    def operand_after(equals_index):
        for end in range(equals_index + 2, min(len(tokens), equals_index + 9) + 1):
            if is_geofence_reference(tokens[equals_index + 1:end]):
                return equals_index + 1, end - 1
        return None

    for equals_index, token in enumerate(tokens):
        if token.value != '=':
            continue
        left = operand_before(equals_index)
        if left is None:
            continue
        # JOIN 两侧用同一关联键是正常关联条件，即使外围有括号也不属于 q。
        if operand_after(equals_index) is not None:
            continue
        if not in_join_on_context(tokens, left[0], depths):
            matches.append((left[0], equals_index))
    return matches


def has_utc_timezone_after_column(tokens, column_index, window_end):
    suffix = tokens[column_index + 1:min(window_end, column_index + 6)]
    return (
        len(suffix) >= 4
        and identifier_value(suffix[0]) == 'at'
        and identifier_value(suffix[1]) == 'time'
        and identifier_value(suffix[2]) == 'zone'
        and suffix[3].kind == 'string'
        and suffix[3].value.lower() == 'utc'
    )


def naive_now_interval_matches(tokens):
    matches = []
    for _, start, close in find_function_calls(tokens, 'now'):
        if close + 2 >= len(tokens) or tokens[close + 1].value != '-' or identifier_value(tokens[close + 2]) != 'interval':
            continue
        window_start = max(0, start - 24)
        window_end = min(len(tokens), close + 10)
        naive = []
        for index in range(window_start, window_end):
            name = identifier_value(tokens[index])
            if name in NAIVE_DATE_COLUMNS and not has_utc_timezone_after_column(tokens, index, window_end):
                naive.append(name)
        if naive:
            matches.append((start, close + 2, tuple(sorted(set(naive)))))
    return matches


def visible_text_allowed(value):
    stripped = value.strip()
    if CJK_RE.search(value):
        return True
    if stripped.lower() in VISIBLE_TEXT_EXACT_ALLOWLIST:
        return True
    if not stripped or stripped.isdecimal():
        return True
    if GRAFANA_PLACEHOLDER_RE.fullmatch(stripped) or REGEX_PLACEHOLDER_RE.fullmatch(stripped):
        return True
    # 纯符号（可含数字）允许；一旦出现字母或下划线，就必须由上面的显式类别放行。
    return not any(character.isalpha() or character == '_' for character in stripped)


def output_field_matches(matcher, field):
    """Grafana 变量替换后的动态别名也视为可确定输出，如 distance_$length_unit → distance_km。"""
    if matcher == field:
        return True
    parts = []
    cursor = 0
    variable_re = re.compile(r'\$(?:\{[A-Za-z_][A-Za-z0-9_]*(?::[^{}]+)?\}|[A-Za-z_][A-Za-z0-9_]*)')
    for match in variable_re.finditer(field):
        parts.append(re.escape(field[cursor:match.start()]))
        parts.append(r'[A-Za-z0-9_]+')
        cursor = match.end()
    if not parts:
        return False
    parts.append(re.escape(field[cursor:]))
    return re.fullmatch(''.join(parts), matcher) is not None


def override_properties_hash(properties):
    """属性数组按“多重集合”规范化；属性顺序不影响键，重复属性仍会保留。"""
    canonical_properties = sorted(
        json.dumps(prop, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        for prop in (properties or [])
    )
    canonical = json.dumps(canonical_properties, ensure_ascii=False, separators=(',', ':'))
    return 'sha256:' + hashlib.sha256(canonical.encode('utf-8')).hexdigest()


def k_key(file_rel, panel_id, matcher_value, properties_hash):
    return file_rel, panel_id, matcher_value, properties_hash


def k_key_sort_key(key):
    file_rel, panel_id, matcher_value, properties_hash = key
    return file_rel, str(panel_id), matcher_value, properties_hash


def format_k_key(key, count=1):
    file_rel, panel_id, matcher_value, properties_hash = key
    count_suffix = f" × {count}" if count != 1 else ''
    return (
        f"{file_rel} :: panel {panel_id} :: k :: override byName={matcher_value!r} "
        f"propertiesHash={properties_hash}{count_suffix}"
    )


def load_k_baseline(allow_missing=False):
    if not os.path.exists(K_BASELINE_PATH):
        if allow_missing:
            return Counter()
        raise ValueError(
            f"缺少 k 基线文件 {K_BASELINE_PATH}；请显式运行 --update-baseline 创建"
        )

    try:
        with open(K_BASELINE_PATH, encoding='utf-8') as handle:
            document = json.load(handle)
    except Exception as error:
        raise ValueError(f"无法读取 k 基线文件 {K_BASELINE_PATH}: {error}") from error

    if not isinstance(document, dict) or document.get('version') != K_BASELINE_VERSION:
        raise ValueError(
            f"k 基线版本无效：期待 version={K_BASELINE_VERSION}"
        )
    entries = document.get('entries')
    if not isinstance(entries, list):
        raise ValueError("k 基线格式无效：entries 必须是数组")

    baseline = Counter()
    for index, item in enumerate(entries):
        if not isinstance(item, dict):
            raise ValueError(f"k 基线 entries[{index}] 必须是对象")
        file_rel = item.get('file')
        panel_id = item.get('panelId')
        matcher_value = item.get('matcher')
        properties_hash = item.get('propertiesHash')
        count = item.get('count')
        if (
            not isinstance(file_rel, str)
            or not isinstance(panel_id, (int, str))
            or isinstance(panel_id, bool)
            or not isinstance(matcher_value, str)
            or not isinstance(properties_hash, str)
            or not properties_hash.startswith('sha256:')
            or not isinstance(count, int)
            or isinstance(count, bool)
            or count < 1
        ):
            raise ValueError(f"k 基线 entries[{index}] 字段或 count 无效")
        key = k_key(file_rel, panel_id, matcher_value, properties_hash)
        if key in baseline:
            raise ValueError(f"k 基线含重复键（应合并 count）：{format_k_key(key)}")
        baseline[key] = count
    return baseline


def write_k_baseline(current):
    document = {
        'version': K_BASELINE_VERSION,
        'key': ['file', 'panelId', 'matcher', 'propertiesHash'],
        'entries': [
            {
                'file': key[0],
                'panelId': key[1],
                'matcher': key[2],
                'propertiesHash': key[3],
                'count': current[key],
            }
            for key in sorted(current, key=k_key_sort_key)
        ],
    }
    directory = os.path.dirname(K_BASELINE_PATH) or '.'
    with tempfile.NamedTemporaryFile(
        mode='w', encoding='utf-8', dir=directory, prefix='.dashboard-lint-baseline.', delete=False
    ) as handle:
        json.dump(document, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
        temporary_path = handle.name
    os.replace(temporary_path, K_BASELINE_PATH)


def recursive_strings(value, path=''):
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f'{path}.{key}' if path else key
            yield from recursive_strings(child, child_path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from recursive_strings(child, f'{path}[{index}]')
    elif isinstance(value, str):
        yield path, value


def dashboard_link_occurrences(panel):
    for path, value in recursive_strings({key: val for key, val in panel.items() if key != 'panels'}):
        if not (path.endswith('.url') or path == 'url' or path.endswith('.href') or path == 'href'):
            continue
        try:
            parsed = urlsplit(value)
        except ValueError:
            continue
        # 绝对外链（含 //host/path）不属于仓内 dashboard UID 完整性检查。
        if parsed.scheme or parsed.netloc:
            continue
        for match in DASHBOARD_PATH_RE.finditer(parsed.path):
            yield path, match.group(1), value


def config_ref_ids(panel):
    """收集同面板所有 configRefId；不下钻 row 的 child panels。"""
    refs = set()

    def walk(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key == 'panels':
                    continue
                if key == 'configRefId' and isinstance(child, str):
                    refs.add(child)
                else:
                    walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(panel)
    return refs


def draw_styles(panel):
    styles = []
    field_config = panel.get('fieldConfig', {}) or {}
    defaults = field_config.get('defaults', {}) or {}
    custom = defaults.get('custom', {}) or {}
    if custom.get('drawStyle') is not None:
        styles.append(('fieldConfig.defaults.custom.drawStyle', custom.get('drawStyle')))
    for index, override in enumerate(field_config.get('overrides', []) or []):
        for prop_index, prop in enumerate(override.get('properties', []) or []):
            if prop.get('id') == 'custom.drawStyle':
                styles.append((f'fieldConfig.overrides[{index}].properties[{prop_index}]', prop.get('value')))
    return styles


def datasource_uid(value):
    if isinstance(value, dict):
        return value.get('uid')
    return value


def datasource_allowed(value):
    uid = datasource_uid(value)
    if uid in (None, ''):
        return True
    if not isinstance(uid, str):
        return False
    return uid == 'TeslaMate' or GRAFANA_PLACEHOLDER_RE.fullmatch(uid) is not None


def find_rawsql_in_panel(panel):
    """递归找 rawSql，并携带所属 target refId；不下钻 child panels。"""
    found = []

    def walk(obj, path='', target_ref=None, target_path=None):
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == 'panels':
                    continue
                child_path = f'{path}.{key}' if path else key
                if key == 'targets' and isinstance(value, list):
                    for index, target in enumerate(value):
                        ref_id = target.get('refId') if isinstance(target, dict) else None
                        walk(target, f'{child_path}[{index}]', ref_id, f'{child_path}[{index}]')
                elif key == 'rawSql' and isinstance(value, str) and value.strip():
                    found.append(SqlContext(value, target_ref, target_path))
                else:
                    walk(value, child_path, target_ref, target_path)
        elif isinstance(obj, list):
            for index, value in enumerate(obj):
                walk(value, f'{path}[{index}]', target_ref, target_path)

    walk(panel)
    return found


def whitelist_candidates(file_rel, subject, rule):
    return [
        (index, item) for index, item in enumerate(WHITELIST)
        if item['file'] == file_rel and item['subject'] == subject and item['rule'] == rule
    ]


def context_target_allowed(context, condition):
    return context.target_path is not None and context.target_ref in condition['target_refs']


def allow_a(file_rel, subject, context, tokens, used):
    for index, item in whitelist_candidates(file_rel, subject, 'a'):
        condition = item['condition']
        if condition['kind'] == 'group_by_speed_bin' and context_target_allowed(context, condition) and has_group_by_speed_bin(tokens):
            used.add(index)
            return True
    return False


def allow_d(file_rel, subject, context, arg2, tokens, used):
    for index, item in whitelist_candidates(file_rel, subject, 'd'):
        condition = item['condition']
        if not context_target_allowed(context, condition):
            continue
        if condition['kind'] == 'timezone_utc' and is_timezone_utc_expression(arg2):
            used.add(index)
            return True
        if condition['kind'] == 'date_trunc_alias' and is_date_trunc_alias_expression(arg2, tokens):
            used.add(index)
            return True
    return False


def allow_e(file_rel, subject, occurrence, used):
    for index, item in whitelist_candidates(file_rel, subject, 'e'):
        if item['condition'] == occurrence:
            used.add(index)
            return True
    return False


def allow_exact(file_rel, subject, rule, condition, used):
    """新规则沿用同一份细粒度白名单：条件必须整项相等，不能 panel 级放行。"""
    for index, item in whitelist_candidates(file_rel, subject, rule):
        if item['condition'] == condition:
            used.add(index)
            return True
    return False


def sql_snippet(sql, tokens, start, end):
    if not tokens:
        return ''
    char_start = max(0, tokens[start].start - 20)
    char_end = min(len(sql), tokens[end].end + 20)
    return sql[char_start:char_end].replace('\n', ' ')


def main():
    verbose_k = False
    update_baseline = False
    for argument in sys.argv[1:]:
        if argument == '--verbose-k':
            verbose_k = True
        elif argument == '--update-baseline':
            update_baseline = True
        elif argument in {'-h', '--help'}:
            print(
                "用法: bash scripts/check-dashboard-lint.sh "
                "[--verbose-k] [--update-baseline]"
            )
            return
        else:
            print(f"未知参数: {argument}", file=sys.stderr)
            sys.exit(2)

    violations = []
    warnings = []
    exemptions = []
    k_occurrences = []
    used_whitelist = set()
    n_files = 0
    n_panels = 0
    n_vars = 0

    all_files = []
    for pattern in DASHBOARD_GLOBS:
        all_files.extend(sorted(glob.glob(pattern)))

    if not all_files:
        print("未找到任何 dashboard JSON 文件（检查 grafana/dashboards/{zh-cn,internal}/ 是否存在）")
        sys.exit(1)

    dashboards = {}
    for file_rel in all_files:
        n_files += 1
        try:
            with open(file_rel, encoding='utf-8') as file_handle:
                dashboards[file_rel] = json.load(file_handle)
        except Exception as error:
            violations.append(f"{file_rel} :: (整份文件) :: 0 :: JSON 解析失败: {error}")

    dashboard_uids = {
        dashboard.get('uid')
        for dashboard in dashboards.values()
        if isinstance(dashboard.get('uid'), str) and dashboard.get('uid')
    }
    project_functions = installed_function_names()
    custom_function_prefixes = derived_custom_function_prefixes(project_functions)

    def record(file_rel, subject, rule, condition, message):
        if allow_exact(file_rel, subject, rule, condition, used_whitelist):
            return
        if rule in REPORT_RULES:
            warnings.append(f"[report-mode] {file_rel} :: {message}")
        else:
            violations.append(f"{file_rel} :: {message}")

    def check_sql(file_rel, subject, label, context):
        sql = context.sql
        tokens, literals = tokenize_sql(sql)

        for start, end in avg_speed_calls(tokens):
            if not allow_a(file_rel, subject, context, tokens, used_whitelist):
                violations.append(f"{file_rel} :: {label} :: a :: ...{sql_snippet(sql, tokens, start, end)}...")

        for literal in literals:
            if '--' in literal:
                violations.append(f"{file_rel} :: {label} :: b :: 字面量含 --: {literal[:60]!r}")

        for args, _, _ in find_function_calls(tokens, 'timezone'):
            parts = split_top_level_tokens(args)
            if len(parts) != 2 or not string_arg_equals(parts[0], '$__timezone') or is_now_call(parts[1]):
                continue
            if not allow_d(file_rel, subject, context, parts[1], tokens, used_whitelist):
                arg_text = sql[parts[1][0].start:parts[1][-1].end] if parts[1] else ''
                violations.append(
                    f"{file_rel} :: {label} :: d :: timezone('$__timezone', {arg_text[:40]}) 且非允许表达式"
                )

        for start, end in settings_car_id_matches(tokens):
            violations.append(f"{file_rel} :: {label} :: f :: {sql_snippet(sql, tokens, start, end)!r}")

        for start, end in payload_cast_matches(tokens):
            violations.append(
                f"{file_rel} :: {label} :: g :: 未加 NULLIF(NULLIF(...)) 守护: "
                f"...{sql_snippet(sql, tokens, start, end)}"
            )

        for name in sorted(function_call_names(tokens)):
            if name in project_functions or not looks_like_custom_function(name, custom_function_prefixes):
                continue
            condition = {
                'kind': 'undefined_custom_function',
                'target_path': context.target_path,
                'value': name,
            }
            record(
                file_rel, subject, 'l', condition,
                f"{label} :: l :: 调用了未定义的自研函数: {name}()",
            )

        for start, end, kind in mod_or_date_part_matches(tokens):
            snippet = sql_snippet(sql, tokens, start, end)
            condition = {
                'kind': 'banned_sql_function',
                'target_path': context.target_path,
                'value': kind,
                'snippet': snippet,
            }
            record(
                file_rel, subject, 'p', condition,
                f"{label} :: p :: 禁止 {kind}: ...{snippet}...",
            )

        for start, end in geofence_equality_matches(tokens):
            snippet = sql_snippet(sql, tokens, start, end)
            condition = {
                'kind': 'nullable_geofence_equality',
                'target_path': context.target_path,
                'snippet': snippet,
            }
            record(
                file_rel, subject, 'q', condition,
                f"{label} :: q :: 可空列 geofence_id 使用直等: ...{snippet}...",
            )

        for start, end, columns in naive_now_interval_matches(tokens):
            snippet = sql_snippet(sql, tokens, start, end)
            condition = {
                'kind': 'naive_date_now_interval',
                'target_path': context.target_path,
                'columns': columns,
                'snippet': snippet,
            }
            record(
                file_rel, subject, 'r', condition,
                f"{label} :: r :: NOW() - interval 邻域含朴素列 {','.join(columns)} 且无 AT TIME ZONE 'UTC': "
                f"...{snippet}...",
            )

        if has_legacy_variable_code_token(tokens):
            condition = {'kind': 'legacy_variable_syntax', 'target_path': context.target_path}
            record(
                file_rel, subject, 's', condition,
                f"{label} :: s :: rawSql/query 含老变量语法 [[",
            )

    for file_rel, dashboard in dashboards.items():
        seen_panel_ids = {}

        def check_panel(panel, panel_path):
            nonlocal n_panels
            n_panels += 1
            panel_id = panel.get('id', '?')
            title = panel.get('title') or ''
            label = f"panel {panel_id}" + (f" {title!r}" if title else "")

            if panel_id != '?':
                if panel_id in seen_panel_ids:
                    condition = {
                        'kind': 'duplicate_panel_id',
                        'value': panel_id,
                        'first_path': seen_panel_ids[panel_id],
                        'duplicate_path': panel_path,
                    }
                    record(
                        file_rel, panel_id, 't', condition,
                        f"{label} :: t :: panel id 重复；首次 {seen_panel_ids[panel_id]}，再次 {panel_path}",
                    )
                else:
                    seen_panel_ids[panel_id] = panel_path

            sql_contexts = find_rawsql_in_panel(panel)
            panel_config_refs = config_ref_ids(panel)
            for context in sql_contexts:
                check_sql(file_rel, panel_id, label, context)

            visible_values = [
                ('title', panel.get('title')),
                ('description', panel.get('description')),
            ]

            field_config = panel.get('fieldConfig', {}) or {}
            defaults = field_config.get('defaults', {}) or {}
            visible_values.append(('fieldConfig.defaults.displayName', defaults.get('displayName')))
            default_unit = defaults.get('unit')
            if default_unit in BANNED_UNITS:
                occurrence = {
                    'kind': 'unit', 'scope': 'defaults', 'matcher_id': None,
                    'matcher_options': None, 'value': default_unit,
                }
                if not allow_e(file_rel, panel_id, occurrence, used_whitelist):
                    violations.append(
                        f"{file_rel} :: {label} :: e :: fieldConfig.defaults.unit = {default_unit!r}"
                    )

            for override_index, override in enumerate(field_config.get('overrides', []) or []):
                matcher = override.get('matcher') or {}
                for prop_index, prop in enumerate(override.get('properties', []) or []):
                    unit = prop.get('value')
                    if prop.get('id') == 'displayName':
                        visible_values.append((
                            f'fieldConfig.overrides[{override_index}].properties[{prop_index}].displayName',
                            prop.get('value'),
                        ))
                    if prop.get('id') != 'unit' or unit not in BANNED_UNITS:
                        continue
                    occurrence = {
                        'kind': 'unit', 'scope': 'override', 'matcher_id': matcher.get('id'),
                        'matcher_options': matcher.get('options'), 'value': unit,
                    }
                    if not allow_e(file_rel, panel_id, occurrence, used_whitelist):
                        violations.append(
                            f"{file_rel} :: {label} :: e :: "
                            f"override[{matcher.get('id')!r}, {matcher.get('options')!r}].unit = {unit!r}"
                        )

            for visible_path, value in visible_values:
                if not isinstance(value, str) or visible_text_allowed(value):
                    continue
                condition = {'kind': 'visible_text', 'path': visible_path, 'value': value}
                record(
                    file_rel, panel_id, 'j', condition,
                    f"{label} :: j :: {visible_path} 未含 CJK 且未整串命中通用白名单: {value!r}",
                )

            if panel.get('type') in {'table', 'stat'}:
                aliases = set()
                has_wildcard = False
                for context in sql_contexts:
                    context_aliases, context_wildcard = top_level_select_fields(tokenize_sql(context.sql)[0])
                    aliases.update(context_aliases)
                    has_wildcard = has_wildcard or context_wildcard
                for override_index, override in enumerate(field_config.get('overrides', []) or []):
                    matcher = override.get('matcher') or {}
                    matcher_value = matcher.get('options')
                    if matcher.get('id') != 'byName' or not isinstance(matcher_value, str):
                        continue
                    if has_wildcard or any(output_field_matches(matcher_value, alias) for alias in aliases):
                        continue
                    condition = {
                        'kind': 'orphan_by_name',
                        'matcher': matcher_value,
                        'aliases': tuple(sorted(aliases)),
                    }
                    properties_hash = override_properties_hash(override.get('properties', []) or [])
                    key = k_key(file_rel, panel_id, matcher_value, properties_hash)
                    k_occurrences.append((
                        key,
                        f"{file_rel} :: {label} :: k :: override byName={matcher_value!r} "
                        f"propertiesHash={properties_hash} 不在顶层 SELECT AS 别名中；"
                        f"已见别名={sorted(aliases)!r}",
                    ))

            for target_index, target in enumerate(panel.get('targets', []) or []):
                if not isinstance(target, dict) or not isinstance(target.get('rawSql'), str) or not target.get('rawSql').strip():
                    continue
                ref_id = target.get('refId', '?')
                if panel.get('type') == 'timeseries' and target.get('format') == 'table':
                    if ref_id in panel_config_refs:
                        exemptions.append(
                            f"{file_rel} :: {label} :: n :: target {ref_id!r} format='table' "
                            "被 configRefId 引用，按配置帧豁免"
                        )
                    else:
                        condition = {'kind': 'timeseries_table_format', 'target_index': target_index, 'ref_id': ref_id}
                        record(
                            file_rel, panel_id, 'n', condition,
                            f"{label} :: n :: target {ref_id!r} format='table'",
                        )

                effective_datasource = target.get('datasource')
                if effective_datasource is None:
                    effective_datasource = panel.get('datasource')
                if not datasource_allowed(effective_datasource):
                    uid = datasource_uid(effective_datasource)
                    condition = {
                        'kind': 'rawsql_datasource',
                        'target_index': target_index,
                        'ref_id': ref_id,
                        'uid': uid,
                    }
                    record(
                        file_rel, panel_id, 'u', condition,
                        f"{label} :: u :: rawSql target {ref_id!r} 写死非 TeslaMate datasource uid={uid!r}",
                    )

            bar_paths = [path for path, value in draw_styles(panel) if value == 'bars']
            transformation_ids = [
                str(item.get('id', ''))
                for item in panel.get('transformations', []) or []
                if isinstance(item, dict)
            ]
            trend_ids = [
                value for value in transformation_ids
                if 'regression' in value.lower() or 'trendline' in value.lower()
            ]
            if bar_paths and trend_ids:
                condition = {
                    'kind': 'bars_trendline',
                    'draw_style_paths': tuple(bar_paths),
                    'transformations': tuple(trend_ids),
                }
                record(
                    file_rel, panel_id, 'o', condition,
                    f"{label} :: o :: drawStyle='bars' 同时挂趋势变换 {trend_ids!r}",
                )

            for link_path, uid, url in dashboard_link_occurrences(panel):
                if uid in dashboard_uids:
                    continue
                condition = {'kind': 'missing_dashboard_uid', 'path': link_path, 'uid': uid}
                record(
                    file_rel, panel_id, 'm', condition,
                    f"{label} :: m :: {link_path} 跳转 uid={uid!r} 不在仓内 {len(dashboard_uids)} 个 dashboard：{url!r}",
                )

            if panel.get('type') == 'volkovlabs-form-panel':
                update = (panel.get('options') or {}).get('update') or {}
                if update.get('method') and update.get('confirm') is False:
                    violations.append(
                        f"{file_rel} :: {label} :: i :: options.update.confirm = false（写操作无二次确认）"
                    )

            for child_index, child in enumerate(panel.get('panels', []) or []):
                check_panel(child, f'{panel_path}.panels[{child_index}]')

        for panel_index, panel in enumerate(dashboard.get('panels', []) or []):
            check_panel(panel, f'panels[{panel_index}]')

        for variable_index, variable in enumerate(dashboard.get('templating', {}).get('list', []) or []):
            n_vars += 1
            name = variable.get('name', '?')
            label = f"var {name}"
            variable_label = variable.get('label')
            if isinstance(variable_label, str) and not visible_text_allowed(variable_label):
                condition = {'kind': 'visible_text', 'path': 'label', 'value': variable_label}
                record(
                    file_rel, name, 'j', condition,
                    f"{label} :: j :: templating.list[{variable_index}].label 未含 CJK 且未整串命中通用白名单: "
                    f"{variable_label!r}",
                )
            if variable.get('type') == 'query':
                query = variable.get('query', '') or ''
                check_sql(file_rel, name, label, SqlContext(query, None, None))
                if '$__timezone' in query:
                    violations.append(
                        f"{file_rel} :: {label} :: c :: 模板变量 query 含 $__timezone（会解析成字面量 browser）"
                    )

            regex = variable.get('regex', '') or ''
            if '(?<text>' in regex or '(?<value>' in regex:
                violations.append(f"{file_rel} :: {label} :: h :: regex 用老式命名捕获组: {regex[:60]!r}")

            for variable_path, value in recursive_strings(variable):
                if variable_path == 'query' or not has_legacy_variable_code_token(tokenize_sql(value)[0]):
                    continue
                condition = {'kind': 'legacy_variable_syntax', 'path': variable_path}
                record(
                    file_rel, name, 's', condition,
                    f"{label} :: s :: 变量字段 {variable_path} 含老变量语法 [[",
                )

    expired = [
        (index, item) for index, item in enumerate(WHITELIST)
        if index not in used_whitelist
    ]

    current_k = Counter(key for key, _ in k_occurrences)
    try:
        baseline_k = load_k_baseline(allow_missing=update_baseline)
    except ValueError as error:
        violations.append(f"{K_BASELINE_PATH} :: k :: {error}")
        baseline_k = Counter()

    baseline_update_refused = update_baseline and bool(violations or expired)
    if baseline_update_refused:
        print(
            "拒绝更新 k 基线：当前树仍有阻断档违规或过期白名单；"
            "基线文件保持不变"
        )
    elif update_baseline:
        added_before_update = current_k - baseline_k
        removed_before_update = baseline_k - current_k
        write_k_baseline(current_k)
        print(
            "k 基线更新："
            f"新增 {sum(added_before_update.values())} 条，"
            f"删除 {sum(removed_before_update.values())} 条，"
            f"现有 {sum(current_k.values())} 条"
        )
        baseline_k = current_k.copy()

    baseline_remaining = baseline_k.copy()
    baseline_messages = []
    added_messages = []
    for key, message in k_occurrences:
        if baseline_remaining[key] > 0:
            baseline_messages.append(message)
            baseline_remaining[key] -= 1
        else:
            added_messages.append(message)
    expired_k = baseline_k - current_k
    baseline_inside_count = sum((current_k & baseline_k).values())

    print(f"k 基线内 {baseline_inside_count} 条，新增 {len(added_messages)} 条")
    if verbose_k and baseline_messages:
        print()
        print("k 基线内明细：")
        print()
        for message in baseline_messages:
            print("  " + message)

    if added_messages:
        print()
        print("k 基线外新增（必须修复或显式更新基线）：")
        print()
        for message in added_messages:
            print("  " + message)

    if expired_k:
        print()
        print("k 过期基线（当前树已消失，必须显式 --update-baseline 收缩）：")
        print()
        for key in sorted(expired_k, key=k_key_sort_key):
            print("  " + format_k_key(key, expired_k[key]))

    if violations:
        print("dashboard lint 发现违规：")
        print()
        for violation in violations:
            print("  " + violation)

    if exemptions:
        if violations:
            print()
        print("dashboard lint 豁免说明：")
        print()
        for exemption in exemptions:
            print("  " + exemption)

    if warnings:
        if violations or exemptions:
            print()
        print("dashboard lint 报告档发现：")
        print()
        for warning in warnings:
            print("  " + warning)

    if expired:
        if violations:
            print()
        print("过期白名单（允许条件本次扫描未命中，必须删除或按现状更新）：")
        print()
        for _, item in expired:
            print(
                f"  {item['file']} :: {item['subject']} :: {item['rule']} :: "
                f"{item['condition']} :: {item['reason']}"
            )

    if violations or expired or added_messages or expired_k:
        print()
        print(
            f"共 {len(violations)} 处违规 / {len(expired)} 条过期白名单 / "
            f"{len(added_messages)} 条新增 k / {sum(expired_k.values())} 条过期 k 基线"
        )
        sys.exit(1)

    report_suffix = f"；报告档 {len(warnings)} 条 WARNING" if warnings else ""
    print(f"✓ dashboard lint 全绿：扫了 {n_files} 文件 / {n_panels} 面板 / {n_vars} 变量{report_suffix}")


if __name__ == '__main__':
    main()
PYEOF
