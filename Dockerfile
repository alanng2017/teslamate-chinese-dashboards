# 基于 TeslaMate 官方 Grafana 镜像（锁定版本，避免上游变更导致容器崩溃）
FROM teslamate/grafana:3.0.0

# 标签信息
LABEL maintainer="wjsall"
LABEL description="TeslaMate Grafana with Chinese Dashboards"
LABEL version="1.2.0"

# 强制中文语言设置（关键！）
ENV GF_DEFAULT_LANGUAGE=zh-Hans
ENV GF_USERS_DEFAULT_LANGUAGE=zh-Hans
ENV GF_USERS_DEFAULT_LOCALE=zh-Hans

# 确保数据源 UID 固定为 TeslaMate，避免仪表板无数据
# 先检查是否已存在，避免重复插入导致 YAML 解析错误（容器无限重启）
USER root
RUN grep -q 'uid: TeslaMate' /etc/grafana/provisioning/datasources/datasource.yml || \
    sed -i '/^  - name: TeslaMate$/a\    uid: TeslaMate' \
    /etc/grafana/provisioning/datasources/datasource.yml
USER grafana

# 复制中文 Dashboard 到 TeslaMate 标准位置
COPY grafana/dashboards/zh-cn/*.json /dashboards/

# 复制 Internal Dashboards（路径必须为 /dashboards_internal/，provisioning 监听此路径）
COPY grafana/dashboards/internal/*.json /dashboards_internal/

# 暴露端口
EXPOSE 3000
