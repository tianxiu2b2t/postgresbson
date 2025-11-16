FROM postgres:18-bookworm

RUN set -ex; \
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
    # 安装 Pigsty 扩展 (18 版本，不含 pg_lake)
    apt-get install -y --no-install-recommends \
        postgresql-18-vchord \
        postgresql-18-cron \
        postgresql-18-pg-uint128 \
        postgresql-18-pg-mooncake && \
    \
    # 编译安装 pg_lake (Snowflake-Labs)
    git clone https://github.com/Snowflake-Labs/pg_lake.git /tmp/pg_lake && \
    cd /tmp/pg_lake && \
    make PG_CONFIG=$(which pg_config) && \
    make install && \
    rm -rf /tmp/pg_lake && \
    \
    # 编译安装 postgresbson
    git clone https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' /tmp/postgresbson/Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    cd /tmp/postgresbson && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" CPPFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    rm -rf /tmp/postgresbson && \
    \
    # 清理
    apt-get purge -y --auto-remove git gcc make libbson-dev postgresql-server-dev-18 curl gnupg && \
    apt-get clean && \
    rm -rf /tmp/pigsty-key /etc/apt/keyrings/pigsty.gpg /etc/apt/sources.list.d/pigsty-io.list /var/lib/apt/lists/*

VOLUME ["/var/lib/postgresql/data"]
CMD ["postgres"]
