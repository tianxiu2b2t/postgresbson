FROM postgres:18-bookworm

# ========== 步骤 1: 安装基础构建依赖 ==========
RUN set -ex; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates \
        git gcc g++ make \
        libbson-dev libbson-1.0-0 \
        postgresql-server-dev-18 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ========== 步骤 2: 安装 Pigsty 扩展 ==========
RUN set -ex; \
    curl -fsSL https://repo.pigsty.cc/key -o /tmp/pigsty-key && \
    gpg --dearmor -o /etc/apt/keyrings/pigsty.gpg /tmp/pigsty-key && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/infra generic main" > /etc/apt/sources.list.d/pigsty-io.list && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/pgsql/bookworm bookworm main" >> /etc/apt/sources.list.d/pigsty-io.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-18-vchord \
        postgresql-18-cron \
        postgresql-18-pg-uint128 \
        postgresql-18-pg-mooncake && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/pigsty-key

# ========== 步骤 3: 编译安装 pg_lake (简化版) ==========
RUN set -ex; \
    git clone --recurse-submodules --depth 1 https://github.com/Snowflake-Labs/pg_lake.git /tmp/pg_lake && \
    cd /tmp/pg_lake && \
    make && make install && \
    rm -rf /tmp/pg_lake

# ========== 步骤 4: 编译安装 postgresbson ==========
RUN set -ex; \
    git clone https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' /tmp/postgresbson/Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    cd /tmp/postgresbson && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" CPPFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/x86_64-linux-gnu.conf && \
    ldconfig && \
    rm -rf /tmp/postgresbson

# ========== 步骤 5: 清理构建依赖 ==========
RUN set -ex; \
    apt-get purge -y --auto-remove git gcc g++ make postgresql-server-dev-18 curl gnupg && \
    apt-get clean && \
    rm -rf /etc/apt/keyrings/pigsty.gpg \
        /etc/apt/sources.list.d/pigsty-io.list \
        /var/lib/apt/lists/*

# ========== 步骤 6: 配置扩展自动安装 ==========
RUN echo "#!/bin/bash\n\
set -e\n\
for db in template1 postgres; do\n\
  psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" --dbname \"\$db\" <<-EOSQL\n\
    CREATE EXTENSION IF NOT EXISTS bson;\n\
    CREATE EXTENSION IF NOT EXISTS pg_lakehouse;\n\
    CREATE EXTENSION IF NOT EXISTS vchord;\n\
    CREATE EXTENSION IF NOT EXISTS cron;\n\
    CREATE EXTENSION IF NOT EXISTS uint128;\n\
    CREATE EXTENSION IF NOT EXISTS mooncake;\n\
EOSQL\n\
done" > /docker-entrypoint-initdb.d/01-extensions.sh && \
    chmod +x /docker-entrypoint-initdb.d/01-extensions.sh

VOLUME ["/var/lib/postgresql/data"]
CMD ["postgres"]
