FROM postgres:18-bookworm

# ========== 步骤 1: 安装基础构建依赖 ==========
RUN set -ex; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates \
        git gcc make \
        patch \
        libbson-dev libbson-1.0-0 \
        postgresql-server-dev-18 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ========== 步骤 2: 安装 pgflake (单机优化的 Snowflake ID) ==========
RUN set -ex; \
    git clone --depth 1 https://github.com/dimtion/pgflake.git /tmp/pgflake && \
    cd /tmp/pgflake && \
    make && make install && \
    rm -rf /tmp/pgflake

# ========== 步骤 3: 编译安装 postgresbson ==========
RUN set -ex; \
    git clone --depth 1 https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' /tmp/postgresbson/Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    cd /tmp/postgresbson && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" CPPFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/x86_64-linux-gnu.conf && \
    ldconfig && \
    rm -rf /tmp/postgresbson

# ========== 步骤 4: 清理构建依赖 ==========
RUN set -ex; \
    apt-get purge -y --auto-remove git gcc make postgresql-server-dev-18 curl gnupg patch && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ========== 步骤 5: 配置扩展自动安装 ==========
RUN echo "#!/bin/bash\n\
set -e\n\
for db in template1 postgres; do\n\
  psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" \"\$db\" <<-EOSQL\n\
    CREATE EXTENSION IF NOT EXISTS bson;\n\
    CREATE EXTENSION IF NOT EXISTS pgflake;\n\
EOSQL\n\
done" > /docker-entrypoint-initdb.d/01-extensions.sh && \
    chmod +x /docker-entrypoint-initdb.d/01-extensions.sh

VOLUME ["/var/lib/postgresql/data"]
CMD ["postgres"]