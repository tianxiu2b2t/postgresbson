FROM postgres:18-bookworm

RUN set -ex; \
    # 安装依赖并编译 postgresbson
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates \
        git gcc make patch \
        libbson-dev libbson-1.0-0 \
        postgresql-server-dev-18 && \
    git clone --depth 1 https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' /tmp/postgresbson/Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    cd /tmp/postgresbson && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" CPPFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/x86_64-linux-gnu.conf && \
    ldconfig && \
    rm -rf /tmp/postgresbson && \
    # 清理构建依赖
    apt-get purge -y --auto-remove git gcc make postgresql-server-dev-18 curl gnupg patch && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    # 初始化全局函数
    echo "#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" template1 <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS bson;
    CREATE OR REPLACE FUNCTION snowflake_next_id(worker_id bigint DEFAULT 1)
    RETURNS bigint LANGUAGE plpgsql AS \$\$
    DECLARE
        our_epoch bigint := 1577836800000;
        seq_mask bigint := 4095;
        worker_shift integer := 12;
        timestamp_shift integer := 22;
        current_millis bigint;
        sequence bigint;
    BEGIN
        current_millis := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::bigint;
        sequence := (random() * 4095)::bigint;
        RETURN ((current_millis - our_epoch) << timestamp_shift) |
               ((worker_id & 31) << worker_shift) |
               (sequence & seq_mask);
    END;
    \$\$;
    CREATE SEQUENCE IF NOT EXISTS snowflake_seq INCREMENT 1 MINVALUE 0 MAXVALUE 4095 CYCLE;
    CREATE OR REPLACE FUNCTION bson_objectid()
    RETURNS TEXT LANGUAGE plpgsql AS \$\$
    DECLARE
        timestamp TEXT; machine_id TEXT; process_id TEXT; counter TEXT; result TEXT;
    BEGIN
        timestamp := lpad(to_hex(floor(extract(epoch FROM clock_timestamp()))::bigint), 8, '0');
        machine_id := lpad(to_hex((random() * 4294967295)::bigint), 8, '0');
        machine_id := substring(machine_id from 1 for 6);
        process_id := lpad(to_hex((random() * 65535)::bigint), 4, '0');
        process_id := substring(process_id from 1 for 4);
        IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'bson_counter') THEN
            CREATE SEQUENCE bson_counter INCREMENT 1 MINVALUE 0 MAXVALUE 16777215 CYCLE;
        END IF;
        counter := lpad(to_hex(nextval('bson_counter')::bigint), 6, '0');
        result := timestamp || machine_id || process_id || counter;
        RETURN result;
    END;
    \$\$;
    CREATE OR REPLACE FUNCTION bson_objectid_simple()
    RETURNS TEXT LANGUAGE sql AS \$\$
        SELECT lpad(to_hex(floor(extract(epoch FROM clock_timestamp()))::bigint), 8, '0') ||
               lpad(to_hex((random() * 4294967295)::bigint), 8, '0') ||
               lpad(to_hex((random() * 65535)::bigint), 4, '0') ||
               lpad(to_hex((random() * 16777215)::bigint), 6, '0');
    \$\$;
EOSQL
psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" postgres <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS bson;
EOSQL" > /docker-entrypoint-initdb.d/01-global-functions.sh && \
    chmod +x /docker-entrypoint-initdb.d/01-global-functions.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 CMD pg_isready -U $POSTGRES_USER || exit 1

VOLUME ["/var/lib/postgresql/data"]
EXPOSE 5432

CMD ["postgres"]
