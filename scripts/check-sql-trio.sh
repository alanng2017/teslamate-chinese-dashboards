#!/usr/bin/env bash
# 校验 SQL 三件套（install-coord-functions / install-tou / install-indexes）
# 在所有 5 处用户可见入口中都被引用，避免日后加新 SQL 时漏改某处。
#
# 跑：bash scripts/check-sql-trio.sh
# 退出码：0 = 全 OK；1 = 有遗漏（输出哪个文件少了哪个 SQL）。
#
# 加新 SQL 文件时：
#   1. 加 sql/install-<NEW>.sql
#   2. 修改本脚本顶部 SQL_TRIO 数组，加上 install-<NEW>
#   3. 在 5 处入口加 install-<NEW> 引用
#   4. 重跑本脚本验证

set -euo pipefail

# 加新 SQL 时改这一行（让本脚本成为 source-of-truth）
SQL_TRIO=(install-coord-functions install-tou install-indexes)

# 5 处入口必须都引用所有 SQL 文件
ENTRY_POINTS=(
    "simple-deploy.sh"
    "migrate-from-official.sh"
    "scripts/upgrade.sh"
    "README.md"
    "QUICKSTART.md"
)

cd "$(dirname "$0")/.." || exit 1

fail=0
echo "校验 SQL 三件套引用一致性..."
echo "  期待: ${SQL_TRIO[*]}"
echo

for entry in "${ENTRY_POINTS[@]}"; do
    if [[ ! -f "$entry" ]]; then
        echo "  ✗ $entry: 文件不存在"
        fail=1
        continue
    fi
    missing=()
    for sql in "${SQL_TRIO[@]}"; do
        if ! grep -q "$sql" "$entry"; then
            missing+=("$sql")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "  ✓ $entry"
    else
        echo "  ✗ $entry 漏掉: ${missing[*]}"
        fail=1
    fi
done

# 同时检查 sql/ 目录下是否真的有这些文件
echo
echo "校验 sql/ 目录..."
for sql in "${SQL_TRIO[@]}"; do
    if [[ -f "sql/${sql}.sql" ]]; then
        echo "  ✓ sql/${sql}.sql"
    else
        echo "  ✗ sql/${sql}.sql 不存在"
        fail=1
    fi
done

echo
if [[ $fail -eq 0 ]]; then
    echo "✅ 全部 SQL 三件套引用一致，sql/ 文件都存在"
    exit 0
else
    echo "❌ 发现引用遗漏 / 文件缺失，发版前必须修复"
    echo
    echo "修复指引："
    echo "  - 入口文件漏 SQL：在那个文件里加上对 sql/<missing>.sql 的引用"
    echo "  - sql/ 文件缺失：要么删 SQL_TRIO 里那一项，要么补 sql/<name>.sql"
    exit 1
fi
