#!/usr/bin/env bash
# 扫所有 dashboard JSON 的 templating.current 字段，找环境残留脏值
# 用途：发版前 push 检查，发现脏值就阻止发版（exit 1）
#
# 历史教训：
# - SpeedTemperature.json `car_id.current.text="Maximus"` + `base_url=infoinnova.net`
#   触发 Grafana 12.4 变量 race condition，多车主用户 SQL 「/」语法错（issue #17）
# - tire-pressure.json `base_url=http://192.168.2.249:4000` 内网地址泄露
#
# 检查范围：仅 templating.list[].current（不扫整个 JSON，避免误报地图 URL options）

set -e
cd "$(dirname "$0")/.."

python3 - <<'PYEOF'
import json, glob, re, sys

# 已知合法 current 内容白名单（即使含「可疑字符」也允许）
LEGIT_PREFIXES = (
    'https://tile.openstreetmap.org/',
    'https://wprd01.is.autonavi.com/',
    'https://webst01.is.autonavi.com/',
    'https://mt1.google.com/',
    'https://cartodb-basemaps-',
)

# 脏值 pattern（匹配 = 报警）
DIRTY_PATTERNS = [
    re.compile(r'http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'),    # 内网/外网 IP
    re.compile(r'https?://[^/]*\.(net|com|org|cn|io)\b', re.I),  # 第三方域名
    re.compile(r'localhost', re.I),
    re.compile(r'127\.0\.0\.1'),
    re.compile(r'Maximus', re.I),
    re.compile(r'infoinnova', re.I),
]

# 长小数（计算结果残留嫌疑）
LONG_DECIMAL = re.compile(r'^-?\d+\.\d{5,}$')

errors = []

for f in sorted(glob.glob('grafana/dashboards/zh-cn/*.json') + glob.glob('grafana/dashboards/internal/*.json')):
    j = json.load(open(f))
    for v in j.get('templating', {}).get('list', []):
        cur = v.get('current') or {}
        text = str(cur.get('text', ''))
        val = str(cur.get('value', ''))
        name = v.get('name', '?')

        for s in (text, val):
            if not s: continue
            # 白名单：合法地图 URL prefix
            if any(s.startswith(p) for p in LEGIT_PREFIXES): continue
            # 脏值检测
            for pat in DIRTY_PATTERNS:
                if pat.search(s):
                    errors.append(f'{f}  var={name}  current 含 {pat.pattern!r}: {s[:80]}')
                    break
            else:
                # 长小数（仅 value 字段，text 字段允许长小数标签）
                if s == val and LONG_DECIMAL.match(s):
                    errors.append(f'{f}  var={name}  current.value 含长小数（疑似计算残留）: {val}')

if errors:
    print('❌ 发现 dashboard JSON 环境残留 current 脏值：')
    print()
    for e in errors:
        print(f'   {e}')
    print()
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    print(f'共 {len(errors)} 处。修法：query 类变量 current 改 {{}}，custom 类用合理硬编码 default')
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    sys.exit(1)
else:
    print('✓ 全部 dashboard JSON 的 templating.current 干净，无环境残留')
    sys.exit(0)
PYEOF
