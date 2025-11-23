FROM postgres:18-bookworm

RUN set -ex; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        git gcc make patch \
        libbson-dev libbson-1.0-0 \
        postgresql-server-dev-18 && \
    git clone --depth 1 https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    cd /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/x86_64-linux-gnu.conf && \
    ldconfig && \
    rm -rf /tmp/postgresbson && \
    apt-get purge -y --auto-remove git gcc make postgresql-server-dev-18 patch && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "#!/bin/bash\n\
set -e\n\
for db in template1 postgres; do\n\
  psql -v ON_ERROR_STOP=1 -U \"\\\$POSTGRES_USER\" \"\\\$db\" <<-'EOF'\n\
    CREATE EXTENSION IF NOT EXISTS bson;\n\
    CREATE OR REPLACE FUNCTION snowflake_next_id(worker_id bigint DEFAULT 1)\n\
    RETURNS bigint LANGUAGE plpgsql AS \\$\\$\n\
    DECLARE\n\
        our_epoch bigint := 1577836800000;\n\
        seq_mask bigint := 4095;\n\
        worker_shift integer := 12;\n\
        timestamp_shift integer := 22;\n\
        current_millis bigint;\n\
        sequence bigint;\n\
    BEGIN\n\
        current_millis := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::bigint;\n\
        sequence := (random() * 4095)::bigint;\n\
        RETURN ((current_millis - our_epoch) << timestamp_shift) |\n\
               ((worker_id & 31) << worker_shift) |\n\
               (sequence & seq_mask);\n\
    END;\n\
    \\$\\$;\n\
    CREATE SEQUENCE IF NOT EXISTS snowflake_seq INCREMENT 1 MINVALUE 0 MAXVALUE 4095 CYCLE;\n\
    CREATE OR REPLACE FUNCTION bson_objectid()\n\
    RETURNS TEXT LANGUAGE plpgsql AS \\$\\$\n\
    DECLARE\n\
        timestamp TEXT; machine_id TEXT; process_id TEXT; counter TEXT; result TEXT;\n\
    BEGIN\n\
        timestamp := lpad(to_hex(floor(extract(epoch FROM clock_timestamp()))::bigint), 8, '0');\n\
        machine_id := lpad(to_hex((random() * 4294967295)::bigint), 8, '0');\n\
        machine_id := substring(machine_id from 1 for 6);\n\
        process_id := lpad(to_hex((random() * 65535)::bigint), 4, '0');\n\
        process_id := substring(process_id from 1 for 4);\n\
        IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'bson_counter') THEN\n\
            CREATE SEQUENCE bson_counter INCREMENT 1 MINVALUE 0 MAXVALUE 16777215 CYCLE;\n\
        END IF;\n\
        counter := lpad(to_hex(nextval('bson_counter')::bigint), 6, '0');\n\
        result := timestamp || machine_id || process_id || counter;\n\
        RETURN result;\n\
    END;\n\
    \\$\\$;\n\
    CREATE OR REPLACE FUNCTION bson_objectid_simple()\n\
    RETURNS TEXT LANGUAGE sql AS \\$\\$\n\
        SELECT lpad(to_hex(floor(extract(epoch FROM clock_timestamp()))::bigint), 8, '0') ||\n\
               lpad(to_hex((random() * 4294967295)::bigint), 8, '0') ||\n\
               lpad(to_hex((random() * 65535)::bigint), 4, '0') ||\n\
               lpad(to_hex((random() * 16777215)::bigint), 6, '0');\n\
    \\$\\$;\n\
EOF\ndone" > /docker-entrypoint-initdb.d/01-global-functions.sh && \
    chmod +x /docker-entrypoint-initdb.d/01-global-functions.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 CMD pg_isready -U $POSTGRES_USER || exit 1

VOLUME ["/var/lib/postgresql/data"]
EXPOSE 5432
CMD ["postgres"]