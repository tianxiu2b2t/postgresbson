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

# ========== 步骤 2: 编译安装 postgresbson ==========
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

# ========== 步骤 3: 清理构建依赖 ==========
RUN set -ex; \
    apt-get purge -y --auto-remove git gcc make postgresql-server-dev-18 curl gnupg patch && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ========== 步骤 4: 在 template1 中创建全局函数 ==========
RUN echo "#!/bin/bash\n\
set -e\n\
\n\
# 在 template1 中创建扩展和函数，这样所有新数据库都会继承\n\
psql -v ON_ERROR_STOP=1 --username \"\\$POSTGRES_USER\" \"template1\" <<-EOSQL\n\
    -- 安装 bson 扩展\n\
    CREATE EXTENSION IF NOT EXISTS bson;\n\
    \n\
    -- Snowflake ID 生成函数\n\
    CREATE OR REPLACE FUNCTION snowflake_next_id(worker_id bigint DEFAULT 1)\n\
    RETURNS bigint\n\
    LANGUAGE plpgsql\n\
    AS \\$\\$\n\
    DECLARE\n\
        our_epoch bigint := 1577836800000; -- 2020-01-01 00:00:00\n\
        seq_mask bigint := 4095; -- 2^12 - 1\n\
        worker_shift integer := 12;\n\
        timestamp_shift integer := 22;\n\
        current_millis bigint;\n\
        sequence bigint;\n\
    BEGIN\n\
        -- 获取当前时间戳（毫秒）\n\
        current_millis := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::bigint;\n\
        \n\
        -- 生成序列号（使用随机数模拟）\n\
        sequence := (random() * 4095)::bigint;\n\
        \n\
        -- 组合 Snowflake ID\n\
        RETURN ((current_millis - our_epoch) << timestamp_shift) |\n\
               ((worker_id & 31) << worker_shift) |\n\
               (sequence & seq_mask);\n\
    END;\n\
    \\$\\$;\n\
    \n\
    -- 创建序列号生成器\n\
    CREATE SEQUENCE IF NOT EXISTS snowflake_seq INCREMENT 1 MINVALUE 0 MAXVALUE 4095 CYCLE;\n\
    \n\
    -- BSON ObjectId 生成函数\n\
    CREATE OR REPLACE FUNCTION bson_objectid()\n\
    RETURNS TEXT\n\
    LANGUAGE plpgsql\n\
    AS \\$\\$\n\
    DECLARE\n\
        timestamp TEXT;\n\
        machine_id TEXT;\n\
        process_id TEXT;\n\
        counter TEXT;\n\
        result TEXT;\n\
    BEGIN\n\
        -- 4字节时间戳（Unix 时间戳，十六进制）\n\
        timestamp := lpad(to_hex(floor(extract(epoch FROM clock_timestamp()))::bigint), 8, '0');\n\
        \n\
        -- 5字节机器标识（使用随机数模拟）\n\
        machine_id := lpad(to_hex((random() * 4294967295)::bigint), 8, '0');\n\
        machine_id := substring(machine_id from 1 for 6); -- 取前6个字符（3字节）\n\
        \n\
        -- 2字节进程ID（使用随机数模拟）\n\
        process_id := lpad(to_hex((random() * 65535)::bigint), 4, '0');\n\
        process_id := substring(process_id from 1 for 4);\n\
        \n\
        -- 3字节计数器（使用序列）\n\
        IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'bson_counter') THEN\n\
            CREATE SEQUENCE bson_counter INCREMENT 1 MINVALUE 0 MAXVALUE 16777215 CYCLE;\n\
        END IF;\n\
        counter := lpad(to_hex(nextval('bson_counter')::bigint), 6, '0');\n\
        \n\
        -- 组合 ObjectId\n\
        result := timestamp || machine_id || process_id || counter;\n\
        \n\
        RETURN result;\n\
    END;\n\
    \\$\\$;\n\
    \n\
    -- 简化的 BSON ObjectId 生成函数（使用随机数）\n\
    CREATE OR REPLACE FUNCTION bson_objectid_simple()\n\
    RETURNS TEXT\n\
    LANGUAGE sql\n\
    AS \\$\\$\n\
        SELECT lpad(to_hex(floor(extract(epoch FROM clock_timestamp()))::bigint), 8, '0') ||\n\
               lpad(to_hex((random() * 4294967295)::bigint), 8, '0') ||\n\
               lpad(to_hex((random() * 65535)::bigint), 4, '0') ||\n\
               lpad(to_hex((random() * 16777215)::bigint), 6, '0');\n\
    \\$\\$;\n\
EOSQL\n\
\n\
# 为已存在的 postgres 数据库也安装扩展\n\
psql -v ON_ERROR_STOP=1 --username \"\\$POSTGRES_USER\" \"postgres\" <<-EOSQL\n\
    CREATE EXTENSION IF NOT EXISTS bson;\n\
EOSQL" > /docker-entrypoint-initdb.d/01-global-functions.sh && \
    chmod +x /docker-entrypoint-initdb.d/01-global-functions.sh

# ========== 步骤 5: 设置健康检查 ==========
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pg_isready -U $POSTGRES_USER || exit 1

VOLUME ["/var/lib/postgresql/data"]

EXPOSE 5432

CMD ["postgres"]