FROM postgres:17-bookworm

RUN set -ex; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates git gcc make libbson-dev postgresql-server-dev-17 && \
    curl -fsSL https://repo.pigsty.cc/key -o /tmp/pigsty-key && \
    gpg --dearmor -o /etc/apt/keyrings/pigsty.gpg /tmp/pigsty-key && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/infra generic main" > /etc/apt/sources.list.d/pigsty-io.list && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/pgsql/bookworm bookworm main" >> /etc/apt/sources.list.d/pigsty-io.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-17-vchord \
        postgresql-17-cron \
        postgresql-17-pg-uint128 \
        postgresql-17-pg-mooncake && \
    git clone https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' /tmp/postgresbson/Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    cd /tmp/postgresbson && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" CPPFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    apt-get purge -y --auto-remove git gcc make libbson-dev postgresql-server-dev-17 curl gnupg && \
    apt-get clean && \
    rm -rf /tmp/pigsty-key \
           /etc/apt/keyrings/pigsty.gpg \
           /etc/apt/sources.list.d/pigsty-io.list \
           /var/lib/apt/lists/* \
           /tmp/postgresbson

VOLUME ["/var/lib/postgresql/data"]
CMD ["postgres"]
