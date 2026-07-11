#!/usr/bin/env python3
"""为 dashboard lint 的 ABSENT override 生成可重复的 git 溯源判决书。"""

import argparse
import difflib
import json
import re
import subprocess
import tempfile
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LINT = ROOT / 'scripts/check-dashboard-lint.sh'
BASELINE = ROOT / 'scripts/dashboard-lint-baseline.json'
DEFAULT_OUTPUT = ROOT / 'docs/dashboard-lint-orphan-verdicts.md'
CJK_RE = re.compile(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]')
BEHAVIOR_IDS = {'links', 'unit', 'mappings', 'thresholds'}
GENERIC_DISPLAY_NAMES = {
    'car_id': '车辆ID',
    'drive_id': '行程ID',
    'battery_level': '电池电量',
    'usable_battery_level': '可用电池电量',
    'distance': '距离',
    'efficiency': '效率',
    'odometer': '里程表',
    'outside_temp': '车外温度',
    'cost': '费用',
    'power': '功率',
    'duration_min': '时长',
    'start_date': '开始时间',
    'end_date': '结束时间',
    'range_loss': '续航损失',
}


def run(args, *, check=True):
    completed = subprocess.run(
        args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if check and completed.returncode:
        raise RuntimeError(
            f"命令失败 ({completed.returncode}): {' '.join(args)}\n"
            f"{completed.stdout}{completed.stderr}"
        )
    return completed


def git(*args, check=True):
    return run(['git', *args], check=check).stdout


def load_lint_namespace():
    source = LINT.read_text(encoding='utf-8')
    marker = 'python3 - "$@" <<\'PYEOF\'\n'
    try:
        python_source = source.split(marker, 1)[1].rsplit('\nPYEOF', 1)[0]
    except IndexError as error:
        raise RuntimeError('无法从 check-dashboard-lint.sh 加载字段契约引擎') from error
    namespace = {'__name__': 'dashboard_lint_contract'}
    exec(compile(python_source, str(LINT), 'exec'), namespace)
    return namespace


def ordered_sql_fields(sql, lint):
    """按最终 SELECT 列序返回列名及去别名后的归一化表达式身份。"""
    if lint['RAW_SQL_VARIABLE_RE'].fullmatch(sql):
        return []
    tokens, _ = lint['tokenize_sql'](sql)
    balance = 0
    select_index = None
    for index, token in enumerate(tokens):
        if token.value == '(':
            balance += 1
        elif token.value == ')':
            balance -= 1
        elif balance == 0 and lint['identifier_value'](token) == 'select':
            select_index = index
            break
    if select_index is None:
        return []
    depth = 0
    end = select_index + 1
    while end < len(tokens):
        token = tokens[end]
        if token.value == '(':
            depth += 1
        elif token.value == ')':
            depth -= 1
        elif depth == 0 and lint['identifier_value'](token) == 'from':
            break
        end += 1

    fields = []
    for raw_expression in lint['split_top_level_tokens'](tokens[select_index + 1:end]):
        expression = lint['trim_select_expression'](raw_expression)
        if not expression:
            fields.append({'name': None, 'expression': ''})
            continue
        alias, expression, _ = lint['select_expression_alias'](expression)
        if alias is not None:
            fields.append({
                'name': alias,
                'expression': lint['normalize_sql_expression'](expression),
            })
            continue
        expr = lint['strip_outer_parens'](expression)
        if len(expr) == 1 and expr[0].kind in {'identifier', 'quoted_identifier'}:
            name = expr[0].value if expr[0].kind == 'quoted_identifier' else expr[0].value.lower()
        elif (
            len(expr) == 3 and expr[1].value == '.'
            and expr[2].kind in {'identifier', 'quoted_identifier'}
        ):
            name = expr[2].value if expr[2].kind == 'quoted_identifier' else expr[2].value.lower()
        else:
            first = lint['identifier_value'](expr[0]) if expr else None
            name = first if first and (first == 'case' or (len(expr) > 1 and expr[1].value == '(')) else '?column?'
        fields.append({
            'name': name,
            'expression': lint['normalize_sql_expression'](expression),
        })
    return fields


def identity_preserving_rename_pairs(old_fields, new_fields):
    """同列数且归一化表达式一致时，才把同位 alias 变化视为改名。"""
    if len(old_fields) != len(new_fields):
        return []
    pairs = []
    for old_column, new_column in zip(old_fields, new_fields):
        if old_column['expression'] != new_column['expression']:
            continue
        if old_column['name'] == new_column['name']:
            continue
        pairs.append((old_column, new_column))
    return pairs


def find_panel(document, panel_id):
    def walk(panels):
        for panel in panels or []:
            if panel.get('id') == panel_id:
                return panel
            found = walk(panel.get('panels'))
            if found is not None:
                return found
        return None
    return walk(document.get('panels'))


def override_matchers(panel):
    if not panel:
        return set()
    return {
        matcher.get('options')
        for override in ((panel.get('fieldConfig') or {}).get('overrides') or [])
        for matcher in [override.get('matcher') or {}]
        if matcher.get('id') == 'byName' and isinstance(matcher.get('options'), str)
    }


def target_map(panel):
    result = {}
    for index, target in enumerate((panel or {}).get('targets') or []):
        if not isinstance(target, dict) or not isinstance(target.get('rawSql'), str):
            continue
        key = target.get('refId', f'index:{index}')
        result[key] = target['rawSql']
    return result


def git_json(spec):
    completed = run(['git', 'show', spec], check=False)
    if completed.returncode:
        return None
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return None


def trace_rename_victims(absent_entries, lint):
    """在每个文件的提交序列中寻找同 panel/target/列序的 SQL alias A→B。"""
    wanted = defaultdict(lambda: defaultdict(set))
    current_fields = {}
    for entry in absent_entries:
        wanted[entry['file']][entry['panelId']].add(entry['matcher'])
        current_fields[(entry['file'], entry['panelId'], entry['matcher'])] = set(entry['fields'])

    verdicts = {}
    for file_rel in sorted(wanted):
        commits = git('log', '--format=%H', '--', file_rel).splitlines()
        unresolved = {
            (panel_id, matcher)
            for panel_id, matchers in wanted[file_rel].items()
            for matcher in matchers
        }
        for commit in commits:
            if not unresolved:
                break
            new_document = git_json(f'{commit}:{file_rel}')
            old_document = git_json(f'{commit}^:{file_rel}')
            if new_document is None or old_document is None:
                continue
            for panel_id, matcher in sorted(unresolved, key=lambda item: (str(item[0]), item[1])):
                new_panel = find_panel(new_document, panel_id)
                old_panel = find_panel(old_document, panel_id)
                if matcher not in override_matchers(new_panel) or matcher not in override_matchers(old_panel):
                    continue
                old_targets = target_map(old_panel)
                new_targets = target_map(new_panel)
                for ref_id in sorted(set(old_targets) & set(new_targets)):
                    old_fields = ordered_sql_fields(old_targets[ref_id], lint)
                    new_fields = ordered_sql_fields(new_targets[ref_id], lint)
                    for old_column, new_column in identity_preserving_rename_pairs(
                        old_fields, new_fields
                    ):
                        old_name = old_column['name']
                        new_name = new_column['name']
                        if old_name != matcher or not new_name or new_name == old_name:
                            continue
                        # 只接受仍能在当前最终字段集合中看到的新名，排除后来又被改走的中间态。
                        if new_name not in current_fields[(file_rel, panel_id, matcher)]:
                            continue
                        subject = git('show', '-s', '--format=%s', commit).strip()
                        verdicts[(file_rel, panel_id, matcher)] = {
                            'old': old_name,
                            'new': new_name,
                            'commit': commit[:12],
                            'subject': subject,
                            'target': ref_id,
                            'expression': old_column['expression'],
                        }
                        break
                    if (file_rel, panel_id, matcher) in verdicts:
                        break
            unresolved = {
                item for item in unresolved if (file_rel, item[0], item[1]) not in verdicts
            }
    return verdicts


def property_ids(entry):
    return [str(prop.get('id', '?')) for prop in entry['properties']]


def has_behavior_property(entry):
    for prop_id in property_ids(entry):
        lowered = prop_id.lower()
        if prop_id in BEHAVIOR_IDS or 'hidden' in lowered or 'hidefrom' in lowered:
            return True
    return False


def is_generic_template_residue(entry):
    expected = GENERIC_DISPLAY_NAMES.get(entry['matcher'])
    if expected is None:
        return False
    display_names = [
        prop.get('value') for prop in entry['properties'] if prop.get('id') == 'displayName'
    ]
    return expected in display_names and not has_behavior_property(entry)


def is_meaningful_p1(entry):
    for prop in entry['properties']:
        prop_id = str(prop.get('id', '')).lower()
        value = prop.get('value')
        if prop.get('id') == 'displayName' and isinstance(value, str) and CJK_RE.search(value):
            return True
        if 'width' in prop_id or 'align' in prop_id:
            return True
    return False


def closest_field(entry):
    fields = [field for field in entry['fields'] if field and field != '?column?']
    if not fields:
        return None
    display_names = [
        prop.get('value') for prop in entry['properties']
        if prop.get('id') == 'displayName' and isinstance(prop.get('value'), str)
    ]
    probes = [entry['matcher'], *display_names]

    def score(field):
        ratios = [difflib.SequenceMatcher(None, probe.lower(), field.lower()).ratio() for probe in probes]
        shared_cjk = max(
            (len(set(CJK_RE.findall(probe)) & set(CJK_RE.findall(field))) for probe in probes),
            default=0,
        )
        return max(ratios) + shared_cjk * 0.15

    candidate = max(sorted(fields), key=score)
    return candidate if score(candidate) >= 0.75 else None


def compact_properties(entry):
    values = []
    for prop in entry['properties']:
        value = json.dumps(prop.get('value'), ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        if len(value) > 70:
            value = value[:67] + '…'
        values.append(f"{prop.get('id', '?')}={value}")
    return '; '.join(values) or '(无属性)'


def md(value):
    return str(value).replace('|', '\\|').replace('\n', '<br>')


def location(entry):
    title = f" {entry['panelTitle']!r}" if entry.get('panelTitle') else ''
    return f"`{entry['file']}` / panel {entry['panelId']}{title}"


def make_row(entry, bucket, rename=None):
    candidate = closest_field(entry)
    if bucket == 'RENAME_VICTIM':
        action = f"将 matcher `{rename['old']}` 改为 `{rename['new']}`，其余 override 属性原样保留。"
        expression = rename['expression']
        if len(expression) > 100:
            expression = expression[:97] + '…'
        evidence = (
            f"target `{rename['target']}` 在 `{rename['commit']}` ({rename['subject']}) "
            f"归一化表达式一致（`{expression}`），仅别名 "
            f"`{rename['old']} → {rename['new']}`，override 未同步。"
        )
    elif bucket == 'P0':
        action = (
            f"默认推荐：恢复字段别名 `{entry['matcher']}`，保留行为属性；备选：删除该 override "
            "并接受属性损失。需 Grafana 预览。"
        )
        candidate_hint = f"；近似字段仅供核对：`{candidate}`" if candidate else ''
        evidence = (
            f"含 links/hidden/mapping/threshold/unit 类行为属性；最终字段：{entry['fields']}"
            f"{candidate_hint}."
        )
    elif bucket == 'P1':
        action = (
            f"默认推荐：恢复字段别名 `{entry['matcher']}`，保留展示属性；备选：删除该 override "
            "并接受属性损失。需 Grafana 预览。"
        )
        candidate_hint = f"；近似字段仅供核对：`{candidate}`" if candidate else ''
        evidence = (
            f"含有意义中文 displayName 或宽度/对齐配置；最终字段：{entry['fields']}"
            f"{candidate_hint}."
        )
    else:
        action = f"删除 matcher `{entry['matcher']}` 对应的通用模板残留 override。"
        evidence = f"无行为级属性，且未找到可信 SQL 改名证据；最终字段：{entry['fields']}."
    return [
        location(entry), f"`{entry['matcher']}`", action, compact_properties(entry), evidence
    ]


def render_table(headers, rows):
    lines = [
        '| ' + ' | '.join(headers) + ' |',
        '| ' + ' | '.join('---' for _ in headers) + ' |',
    ]
    if not rows:
        lines.append('| ' + ' | '.join(['（无）', *([''] * (len(headers) - 1))]) + ' |')
    else:
        lines.extend('| ' + ' | '.join(md(value) for value in row) + ' |' for row in rows)
    return lines


def build_report(contract, baseline, renames, head):
    contract_entries = contract['entries']
    contract_by_key = defaultdict(list)
    for entry in contract_entries:
        key = (entry['file'], entry['panelId'], entry['matcher'], entry['propertiesHash'])
        contract_by_key[key].append(entry)

    absent_entries = []
    for baseline_entry in baseline['entries']:
        key = (
            baseline_entry['file'], baseline_entry['panelId'], baseline_entry['matcher'],
            baseline_entry['propertiesHash'],
        )
        matches = contract_by_key.get(key, [])
        if not matches or any(item['state'] != 'ABSENT' for item in matches):
            raise RuntimeError(f"基线与契约 ABSENT 不一致: {key}")
        for occurrence in range(baseline_entry['count']):
            entry = dict(matches[min(occurrence, len(matches) - 1)])
            entry['occurrence'] = occurrence + 1
            absent_entries.append(entry)

    baseline_count = sum(item['count'] for item in baseline['entries'])
    if len(absent_entries) != baseline_count:
        raise RuntimeError(f"基线展开对账失败: {len(absent_entries)} != {baseline_count}")

    buckets = defaultdict(list)
    for entry in absent_entries:
        rename = renames.get((entry['file'], entry['panelId'], entry['matcher']))
        if rename:
            bucket = 'RENAME_VICTIM'
        elif has_behavior_property(entry):
            bucket = 'P0'
        elif is_generic_template_residue(entry):
            bucket = 'P2'
        elif is_meaningful_p1(entry):
            bucket = 'P1'
        else:
            bucket = 'P2'
        buckets[bucket].append(make_row(entry, bucket, rename))

    verdict_total = sum(len(buckets[name]) for name in ('RENAME_VICTIM', 'P0', 'P1', 'P2'))
    if verdict_total != baseline_count:
        raise RuntimeError(f"判决分桶对账失败: {verdict_total} != {baseline_count}")

    exempt_entries = [entry for entry in contract_entries if entry['state'] in {'DYNAMIC', 'UNKNOWN'}]
    exempt_rows = []
    for entry in exempt_entries:
        reasons = entry['dynamicReasons'] if entry['state'] == 'DYNAMIC' else entry['unknownReasons']
        exempt_rows.append([
            location(entry), f"`{entry['matcher']}`", entry['state'], '; '.join(reasons)
        ])

    counts = Counter(entry['state'] for entry in contract_entries)
    lines = [
        '# Dashboard lint 孤儿 override 判决书',
        '',
        f'> 基于 `{head}` 的最终字段契约与 git 历史生成。背景审计见 '
        '[dashboard-lint-first-run-findings.md](dashboard-lint-first-run-findings.md)。',
        '>',
        '> 执行前提：卡②会按批次在 NAS 上进行 Grafana 预览；所有标注“需 Grafana 预览”的动作'
        '必须预览通过后再落盘。',
        '',
        '## 对账与统计',
        '',
        f'- 四态：PRESENT {counts["PRESENT"]} / ABSENT {counts["ABSENT"]} / '
        f'DYNAMIC {counts["DYNAMIC"]} / UNKNOWN {counts["UNKNOWN"]}。',
        f'- ABSENT 基线：{baseline_count}；判决：RENAME_VICTIM {len(buckets["RENAME_VICTIM"])} / '
        f'P0 {len(buckets["P0"])} / P1 {len(buckets["P1"])} / P2 {len(buckets["P2"])}。',
        f'- 总数对账：{len(buckets["RENAME_VICTIM"])} + {len(buckets["P0"])} + '
        f'{len(buckets["P1"])} + {len(buckets["P2"])} = {verdict_total} = 基线 {baseline_count}。',
        '- 优先级：RENAME_VICTIM（有同 panel/target SQL 改名证据）→ P0（行为失效）→ '
        'P1（有意义展示配置）→ P2（通用模板/低语义残渣）。',
        '',
    ]
    headers = ['位置', 'matcher', '建议动作', 'override 属性', '证据']
    sections = [
        ('RENAME_VICTIM 建议表', 'RENAME_VICTIM'),
        ('P0：行为级失效', 'P0'),
        ('P1：展示属性失效', 'P1'),
        ('P2：通用模板/低语义残渣', 'P2'),
    ]
    for title, name in sections:
        lines.extend([f'## {title}', ''])
        lines.extend(render_table(headers, buckets[name]))
        lines.append('')

    lines.extend(['## DYNAMIC / UNKNOWN 豁免区', ''])
    lines.extend(render_table(['位置', 'matcher', '状态', '豁免原因'], exempt_rows))
    lines.extend([
        '',
        '## 复现',
        '',
        '```bash',
        'python3 scripts/analyze-orphan-overrides.py',
        'bash scripts/check-dashboard-lint.sh --verbose-k',
        '```',
        '',
    ])
    return '\n'.join(lines), buckets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    lint = load_lint_namespace()
    with tempfile.TemporaryDirectory(prefix='dashboard-orphan-analysis-') as directory:
        contract_path = Path(directory) / 'contract.json'
        completed = run([
            'bash', str(LINT.relative_to(ROOT)), '--k-contract-json', str(contract_path)
        ], check=False)
        if completed.returncode:
            raise RuntimeError(
                'lint 未通过，拒绝生成判决书：\n' + completed.stdout + completed.stderr
            )
        contract = json.loads(contract_path.read_text(encoding='utf-8'))

    baseline = json.loads(BASELINE.read_text(encoding='utf-8'))
    absent_entries = [entry for entry in contract['entries'] if entry['state'] == 'ABSENT']
    renames = trace_rename_victims(absent_entries, lint)
    head = git('rev-parse', '--short=12', 'HEAD').strip()
    report, buckets = build_report(contract, baseline, renames, head)

    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name('.' + output.name + '.tmp')
    temporary.write_text(report, encoding='utf-8')
    temporary.replace(output)
    baseline_count = sum(item['count'] for item in baseline['entries'])
    try:
        display_output = output.relative_to(ROOT)
    except ValueError:
        display_output = output
    print(
        f"已生成 {display_output}：基线 {baseline_count} 条；"
        f"RENAME_VICTIM {len(buckets['RENAME_VICTIM'])} / P0 {len(buckets['P0'])} / "
        f"P1 {len(buckets['P1'])} / P2 {len(buckets['P2'])}"
    )


if __name__ == '__main__':
    main()
