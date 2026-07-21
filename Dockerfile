# 基于 TeslaMate 官方 Grafana 镜像（跟随上游 :latest，随上游 Grafana 版本滚动；
# 不锁定——Grafana 13.0.1 已用我们 45+3 个面板 + volkovlabs-form-panel 6.3.2 实测兼容）
FROM teslamate/grafana:latest

# 强制中文语言设置（关键！）
ENV GF_USERS_DEFAULT_LANGUAGE=zh-Hans
ENV GF_USERS_DEFAULT_LOCALE=zh-Hans

# 数据库连接默认值（用户未设置时自动生效，兼容方法四只替换镜像的场景）
ENV DATABASE_PORT=5432
ENV DATABASE_SSL_MODE=disable

# build-time 安装「⚡ 分时电价配置」面板所需插件
# v1.6.3 起改用 build-time grafana cli（不用 ENV）— 详见 v1.6.3 CHANGELOG 和 issue #13
# 第三方依赖：https://github.com/VolkovLabs/volkovlabs-form-panel （Apache 2.0，签名验证）
# chown 472:0 = grafana user (uid 472, root group 0) — 与上游 teslamate/grafana 的 GF_UID/GF_GID 一致，
# 不同于 NAS 仪表盘文件场景的 472:472（CLAUDE.md 第六节）
USER root
RUN rm -f /etc/grafana/provisioning/datasources/*.yml \
          /etc/grafana/provisioning/datasources/*.yaml \
          /etc/grafana/provisioning/dashboards/*.yml \
          /etc/grafana/provisioning/dashboards/*.yaml \
 && grafana cli --pluginsDir /var/lib/grafana/plugins plugins install volkovlabs-form-panel 6.3.2 \
 && chown -R 472:0 /var/lib/grafana/plugins

# 写入唯一的数据源配置 + 覆盖基础镜像 dashboard provisioning（避免 ×2 报错）
COPY grafana/provisioning/datasources/datasource.yml \
     /etc/grafana/provisioning/datasources/datasource.yml
COPY dashboards.yml \
     /etc/grafana/provisioning/dashboards/dashboards.yml
USER grafana

# 复制中文 Dashboard 到 TeslaMate 标准位置
COPY grafana/dashboards/zh-cn/*.json /dashboards/

# 复制 Internal Dashboards（路径必须为 /dashboards_internal/，provisioning 监听此路径）
COPY grafana/dashboards/internal/*.json /dashboards_internal/

# 暴露端口
EXPOSE 3000

# 标签信息（故意放在文件最末尾，而不是紧跟 FROM）
# 原因：ARG VERSION 的值每次发版都变，Docker 会把它计入"首次使用它的指令"（LABEL version）的
# cache key；一旦这层 cache miss，它之后的所有层也会连带 miss。如果这两行留在文件靠前的位置，
# 会连累上面昂贵的插件安装 RUN（grafana cli plugins install）和 COPY 层，导致每次 tag 发版
# 都重装一遍插件（×2 架构，linux/amd64 + linux/arm64）。挪到最后，VERSION 变化只作废这条
# 极轻的 LABEL 层本身，前面所有层继续命中缓存。
# maintainer/description 是固定值，理论上放哪都不影响缓存，为了避免 LABEL 声明分散在两处，
# 一并挪到这里。
# version 由 CI 通过 --build-arg 注入真实版本号，见 .github/workflows/ghcr-build.yml；
# 本地不传参构建时默认 "dev"，不会假冒成某个已发布的正式版本号。
ARG VERSION=dev
LABEL maintainer="wjsall"
LABEL description="TeslaMate Grafana with Chinese Dashboards"
LABEL version="${VERSION}"
