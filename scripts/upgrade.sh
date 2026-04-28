#!/bin/bash
# TeslaMate 中文仪表盘 — 一键升级脚本
#
# 用法（在仓库根目录运行）:
#   bash scripts/upgrade.sh
#
# 自动完成:
#   1. git pull 拉取最新代码
#   2. 自动检测运行中的 PostgreSQL 容器名
#   3. 安装/更新坐标转换函数（lat_for_map / lng_for_map / wgs84_to_gcj02_*）
#   4. 重启 Grafana 容器，触发仪表盘重载
#
# 适用场景:
#   - 从 v1.4.1 或更早版本升级到 v1.4.2+
#   - v1.4.2+ 全新安装后第一次启用地图源切换功能
#   - 任何时候想确保坐标转换函数是最新的
set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# ============================================================
# 0. 检查工作目录
# ============================================================
if [ ! -f "sql/install-coord-functions.sql" ]; then
    echo -e "${RED}✗ 错误：找不到 sql/install-coord-functions.sql${NC}"
    echo "  请确认你在 teslamate-chinese-dashboards 仓库根目录运行此脚本。"
    exit 1
fi

# ============================================================
# 1. git pull
# ============================================================
echo -e "${BLUE}[1/4] 拉取最新代码...${NC}"
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${RED}✗ 本地有未提交的修改，无法 git pull${NC}"
    echo ""
    echo "  请先处理本地改动（任选一）:"
    echo "    git stash                # 暂存到栈，pull 完后 git stash pop"
    echo "    git commit -am 'wip'     # 提交"
    echo "    git restore .            # 放弃所有未提交改动（危险）"
    echo ""
    echo "  处理后重新运行: bash scripts/upgrade.sh"
    exit 1
fi
git pull --rebase

# ============================================================
# 2. 检测 PostgreSQL 容器名
# ============================================================
echo -e "${BLUE}[2/4] 检测 PostgreSQL 容器...${NC}"
DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'teslamate.*database|teslamate.*postgres' | head -1)

if [ -z "$DB_CONTAINER" ]; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE '^database$|^postgres$' | head -1)
fi

if [ -z "$DB_CONTAINER" ]; then
    echo -e "${RED}✗ 找不到运行中的 PostgreSQL 容器${NC}"
    echo ""
    echo "  请先启动 TeslaMate："
    echo "    docker compose up -d"
    echo ""
    echo "  或手动指定容器名后再跑函数安装："
    echo "    docker exec -i <你的容器名> psql -U teslamate teslamate \\"
    echo "      < sql/install-coord-functions.sql"
    exit 1
fi
echo -e "${GREEN}  ✓ 找到容器: ${DB_CONTAINER}${NC}"

# ============================================================
# 3. 安装坐标转换函数
# ============================================================
echo -e "${BLUE}[3/4] 安装 PostgreSQL 坐标转换函数...${NC}"
if ! docker exec -i "$DB_CONTAINER" psql -U teslamate -d teslamate \
        < sql/install-coord-functions.sql; then
    echo -e "${RED}✗ 函数安装失败${NC}"
    echo "  常见原因 + 解决: 见 TROUBLESHOOTING.md「装 PostgreSQL 坐标转换函数报错」章节"
    exit 1
fi

# ============================================================
# 4. 重启 Grafana
# ============================================================
echo -e "${BLUE}[4/4] 重启 Grafana...${NC}"
GRAFANA_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'teslamate.*grafana|^grafana$' | head -1)
if [ -n "$GRAFANA_CONTAINER" ]; then
    docker restart "$GRAFANA_CONTAINER" > /dev/null
    echo -e "${GREEN}  ✓ 已重启 ${GRAFANA_CONTAINER}${NC}"
else
    echo -e "${YELLOW}  ⚠ 没找到运行中的 Grafana 容器，跳过重启${NC}"
    echo "    Grafana 默认 10 秒内会自动检测到仪表盘 JSON 变化。"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ 升级完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "下一步:"
echo "  1. 浏览器 Ctrl+Shift+R（Windows）/ Cmd+Shift+R（Mac）强刷"
echo "  2. 打开任一含地图的仪表盘:"
echo "     • 当前驾驶状态  • 当前充电状态  • 驾驶记录追踪"
echo "     • 充电统计      • 行程统计      • 足迹地图"
echo "  3. 顶部「地图源」下拉框试试切换 → 高德/谷歌/卫星"
echo ""
echo "如有问题: TROUBLESHOOTING.md"
