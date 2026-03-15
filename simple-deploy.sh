#!/bin/bash
# TeslaMate 中文 Dashboard 一键安装脚本
# 5分钟完成 TeslaMate + 中文 Grafana Dashboard 部署

set -e

echo "=============================================="
echo "  TeslaMate 中文 Dashboard 一键安装脚本"
echo "=============================================="
echo ""
echo "📦 安装内容："
echo "  - TeslaMate 后端"
echo "  - PostgreSQL 数据库"
echo "  - Grafana + 中文 Dashboard（31个）"
echo "  - MQTT 自动连接车辆"
echo ""
echo "⏱️  预计耗时：5-10 分钟"
echo ""

# 检查 Docker 和 Docker Compose
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装"
    echo ""
    echo "请先安装 Docker："
    echo "  Ubuntu: curl -fsSL https://get.docker.com | bash"
    echo "  CentOS: sudo yum install docker"
    echo ""
    exit 1
fi

if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose 未安装"
    echo ""
    echo "请先安装 Docker Compose"
    exit 1
fi

# 创建工作目录
INSTALL_DIR="${HOME}/teslamate-chinese"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "📁 工作目录: $INSTALL_DIR"
echo ""

# 获取 MQTT 令牌（必需）
echo "🔐 需要配置 Tesla 账号信息"
echo ""
read -p "Tesla 账号邮箱: " TESLA_EMAIL
read -sp "Tesla 密码: " TESLA_PASSWORD
echo ""
read -p "MQTT 令牌 (如不知道留空): " MQTT_TOKEN

# 生成 docker-compose.yml
echo "📝 生成配置文件..."

cat > docker-compose.yml << 'EOF'
version: "3"

services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    stop_grace_period: 1m
    ports:
      - 4000:4000
    volumes:
      - ./import:/opt/app/import
      - ./teslamate-data:/var/lib/teslamate
    environment:
      - ENCRYPTION_KEY=INSERT_RANDOM_KEY_HERE
      - DATABASE_USER=teslamate
      - DATABASE_PASS=password
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
      - MQTT_USERNAME=teslamate
      - MQTT_PASSWORD=secret

  database:
    image: postgres:15
    restart: always
    volumes:
      - ./db-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=teslamate

  grafana:
    image: ghcr.io/wjsall/teslamate-chinese-dashboards:latest
    restart: always
    ports:
      - 3000:3000
    volumes:
      - ./grafana-data:/var/lib/grafana
    environment:
      - GF_USERS_DEFAULT=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=grafana-worldmap-panel
      - GF_DEFAULT_LANGUAGE=zh-Hans
    depends_on:
      - teslamate

  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    ports:
      - 1883:1883
    volumes:
      - ./mosquitto-config:/mosquitto/config
      - ./mosquitto-data:/mosquitto/data
EOF

# 创建 mosquitto 配置
mkdir -p mosquitto-config
cat > mosquitto-config/mosquitto.conf << 'EOF'
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
EOF

# 生成 mosquitto 密码文件
touch mosquitto-config/passwd

# 生成随机加密密钥
ENCRYPTION_KEY=$(openssl rand -hex 32)
sed -i "s/INSERT_RANDOM_KEY_HERE/$ENCRYPTION_KEY/" docker-compose.yml

echo ""
echo "✅ 配置文件已生成"
echo ""

# 启动服务
echo "🚀 启动服务（首次启动需要下载镜像，请耐心等待）..."
docker compose up -d

echo ""
echo "⏳ 等待服务启动..."
sleep 30

# 检查服务状态
echo ""
echo "📊 服务状态:"
docker compose ps

echo ""
echo "=============================================="
echo "✅ 安装完成！"
echo "=============================================="
echo ""
echo "📱 访问地址："
echo "  - TeslaMate:  http://localhost:4000"
echo "  - Grafana:     http://localhost:3000"
echo ""
echo "🔐 Grafana 登录信息："
echo "  - 用户名: admin"
echo "  - 密码: admin"
echo ""
echo "📝 下一步："
echo "  1. 访问 TeslaMate: http://localhost:4000"
echo "  2. 登录 Tesla 账号"
echo "  3. 车辆会自动开始同步数据"
echo "  4. 几分钟后访问 Grafana 查看中文 Dashboard"
echo ""
echo "📚 相关文档："
echo "  - 场景速查手册: SCENE_GUIDE.md"
echo "  - 数据指标手册: METRICS_GUIDE.md"
echo "  - 功能地图:     DASHBOARD_MAP.md"
echo ""
echo "🆘 遇到问题？"
echo "  查看日志: docker compose logs -f"
echo "  重启服务: docker compose restart"
echo ""
