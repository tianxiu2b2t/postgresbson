# 基础镜像：Postgres 18 (bookworm)
FROM postgres:18-bookworm

RUN set -ex; \
    # 安装基础构建依赖和运行时依赖
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates \
        git gcc make \
        libbson-dev libbson-1.0-0 \
        postgresql-server-dev-18 && \
    \
    # 配置 Pigsty 仓库
    curl -fsSL https://repo.pigsty.cc/key -o /tmp/pigsty-key && \
    gpg --dearmor -o /etc/apt/keyrings/pigsty.gpg /tmp/pigsty-key && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/infra generic main" > /etc/apt/sources.list.d/pigsty-io.list && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/pgsql/bookworm bookworm main" >> /etc/apt/sources.list.d/pigsty-io.list && \
    apt-get update && \
    \
    # 安装 Pigsty 扩展 (18 版本)
    apt-get install -y --no-install-recommends \
        postgresql-18-vchord \
        postgresql-18-cron \
        postgresql-18-pg-uint128 \
        postgresql-18-pg-mooncake \
        postgresql-18-pg-lake && \
    \
    # 拉取并编译 postgresbson
    git clone https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' /tmp/postgresbson/Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    cd /tmp/postgresbson && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" CPPFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    \
    # 确保动态库路径被 ld 识别
    echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/x86_64-linux-gnu.conf && \
    ldconfig && \
    \
    # 清理开发依赖和临时文件，仅保留运行时依赖
    apt-get purge -y --auto-remove git gcc make libbson-dev postgresql-server-dev-18 curl gnupg && \
    apt-get clean && \
    rm -rf /tmp/pigsty-key \
        /etc/apt/keyrings/pigsty.gpg \
        /etc/apt/sources.list.d/pigsty-io.list \
        /var/lib/apt/lists/* \
        /tmp/postgresbson

# 数据目录
VOLUME ["/var/lib/postgresql/data"]

# 默认启动命令
CMD ["postgres"]
