#!/usr/bin/env bash
# dashboard JSON 静态 lint 门：把本项目踩过的 9 类真实坑变成可执行检查。
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
#
# a/d/f/g 共用一次 PostgreSQL-lite 词法扫描后的代码 token 流（注释已剔除，字符串保留为
# 有类型 token）；b 只检查同一扫描产出的字符串字面量内容。白名单不是 panel 级开关：
# 每条都带可校验条件；本次扫描未命中的条目视为过期白名单并直接失败。

set -e
cd "$(dirname "$0")/.."

python3 - <<'PYEOF'
import glob
import json
import re
import sys
from collections import namedtuple


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
    ('grafana/dashboards/internal/drive-details.json', 39, 'override', 'byRegexp', '.*_mi$', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/internal/drive-details.json', 40, 'defaults', None, None, 'kwatth', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/ContinuousTrips.json', 2, 'override', 'byName', 'distance_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentDriveView.json', 14, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentDriveView.json', 14, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 69, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 69, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 70, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/CurrentState.json', 70, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/TrackingDrives.json', 12, 'override', 'byName', 'km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/TrackingDrives.json', 12, 'override', 'byName', 'mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/TrackingDrives.json', 16, 'defaults', None, None, 'kwatth', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/battery-health.json', 14, 'override', 'byRegexp', '/.*_mi/', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/charges.json', 6, 'override', 'byName', 'range_added_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/charges.json', 6, 'override', 'byName', 'range_added_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/drive-stats.json', 8, 'override', 'byName', 'distance_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/drive-stats.json', 26, 'override', 'byName', 'distance_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/drives.json', 2, 'override', 'byName', 'distance_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/overview.json', 25, 'override', 'byName', 'range_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/overview.json', 25, 'override', 'byName', 'range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/trip.json', 2, 'override', 'byName', 'distance_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/trip.json', 36, 'override', 'byName', 'range_added_km', 'lengthkm', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/trip.json', 36, 'override', 'byName', 'range_added_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/trip.json', 42, 'override', 'byRegexp', '.*_mi$', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/updates.json', 2, 'override', 'byName', 'avg_ideal_range_mi', 'lengthmi', _DRILLDOWN),
    ('grafana/dashboards/zh-cn/updates.json', 2, 'override', 'byName', 'avg_rated_range_mi', 'lengthmi', _DRILLDOWN),
    (
        'grafana/dashboards/zh-cn/vampire-drain.json', 2, 'override', 'byName',
        'range_diff_mi', 'lengthmi',
        "已知挂账：仅放行 range_diff_mi=lengthmi；range_diff_km 必须保持字符串单位 km",
    ),
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
            while j < n and (sql[j].isalnum() or sql[j] in '_$' or ord(sql[j]) >= 128):
                j += 1
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


def sql_snippet(sql, tokens, start, end):
    if not tokens:
        return ''
    char_start = max(0, tokens[start].start - 20)
    char_end = min(len(sql), tokens[end].end + 20)
    return sql[char_start:char_end].replace('\n', ' ')


def main():
    violations = []
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

    for file_rel in all_files:
        n_files += 1
        try:
            with open(file_rel, encoding='utf-8') as file_handle:
                dashboard = json.load(file_handle)
        except Exception as error:
            violations.append(f"{file_rel} :: (整份文件) :: 0 :: JSON 解析失败: {error}")
            continue

        def check_panel(panel):
            nonlocal n_panels
            n_panels += 1
            panel_id = panel.get('id', '?')
            title = panel.get('title') or ''
            label = f"panel {panel_id}" + (f" {title!r}" if title else "")

            for context in find_rawsql_in_panel(panel):
                check_sql(file_rel, panel_id, label, context)

            field_config = panel.get('fieldConfig', {}) or {}
            defaults = field_config.get('defaults', {}) or {}
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

            for override in field_config.get('overrides', []) or []:
                matcher = override.get('matcher') or {}
                for prop in override.get('properties', []) or []:
                    unit = prop.get('value')
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

            if panel.get('type') == 'volkovlabs-form-panel':
                update = (panel.get('options') or {}).get('update') or {}
                if update.get('method') and update.get('confirm') is False:
                    violations.append(
                        f"{file_rel} :: {label} :: i :: options.update.confirm = false（写操作无二次确认）"
                    )

            for child in panel.get('panels', []) or []:
                check_panel(child)

        for panel in dashboard.get('panels', []) or []:
            check_panel(panel)

        for variable in dashboard.get('templating', {}).get('list', []) or []:
            n_vars += 1
            name = variable.get('name', '?')
            label = f"var {name}"
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

    expired = [
        (index, item) for index, item in enumerate(WHITELIST)
        if index not in used_whitelist
    ]

    if violations:
        print("dashboard lint 发现违规：")
        print()
        for violation in violations:
            print("  " + violation)

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

    if violations or expired:
        print()
        print(f"共 {len(violations)} 处违规 / {len(expired)} 条过期白名单")
        sys.exit(1)

    print(f"✓ dashboard lint 全绿：扫了 {n_files} 文件 / {n_panels} 面板 / {n_vars} 变量")


if __name__ == '__main__':
    main()
PYEOF
