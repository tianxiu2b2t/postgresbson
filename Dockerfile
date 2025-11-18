FROM postgres:18-bookworm

# ========== 步骤 1: 安装所有构建依赖 ==========
RUN set -ex; \
    apt-get update && \
    apt-get install -y \
        build-essential \
        cmake \
        ninja-build \
        libreadline-dev \
        zlib1g-dev \
        flex \
        bison \
        libxml2-dev \
        libxslt1-dev \
        libicu-dev \
        libssl-dev \
        libgeos-dev \
        libproj-dev \
        libgdal-dev \
        libjson-c-dev \
        libprotobuf-c-dev \
        protobuf-c-compiler \
        diffutils \
        uuid-dev \
        libossp-uuid-dev \
        liblz4-dev \
        liblzma-dev \
        libsnappy-dev \
        perl \
        libtool \
        libjansson-dev \
        libcurl4-openssl-dev \
        curl \
        zip \
        unzip \
        tar \
        patch \
        g++ \
        libipc-run-perl \
        jq \
        git \
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

# ========== 步骤 3: 安装 vcpkg 和 Azure 依赖 ==========
RUN set -ex; \
    export VCPKG_VERSION=2025.01.13 && \
    git clone --recurse-submodules https://github.com/Microsoft/vcpkg.git /opt/vcpkg && \
    cd /opt/vcpkg && \
    ./bootstrap-vcpkg.sh && \
    ./vcpkg install azure-identity-cpp azure-storage-blobs-cpp azure-storage-files-datalake-cpp openssl

ENV VCPKG_TOOLCHAIN_PATH=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake

# ========== 步骤 4: 编译安装 pg_lake ==========
RUN set -ex; \
    git clone --recurse-submodules https://github.com/snowflake-labs/pg_lake.git /tmp/pg_lake && \
    cd /tmp/pg_lake/duckdb_pglake && \
    make && make install && \
    cd /tmp/pg_lake && \
    make install-avro-local && \
    make fast && \
    make install-fast && \
    rm -rf /tmp/pg_lake

# ========== 步骤 5: 编译安装 postgresbson ==========
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

# ========== 步骤 6: 配置 PostgreSQL ==========
RUN echo "shared_preload_libraries = 'pg_extension_base'" >> /usr/share/postgresql/postgresql.conf.sample

# ========== 步骤 7: 清理构建依赖 ==========
RUN set -ex; \
    apt-get purge -y --auto-remove \
        build-essential \
        cmake \
        ninja-build \
        libreadline-dev \
        zlib1g-dev \
        flex \
        bison \
        libxml2-dev \
        libxslt1-dev \
        libicu-dev \
        libssl-dev \
        libgeos-dev \
        libproj-dev \
        libgdal-dev \
        libjson-c-dev \
        libprotobuf-c-dev \
        protobuf-c-compiler \
        uuid-dev \
        libossp-uuid-dev \
        liblz4-dev \
        liblzma-dev \
        libsnappy-dev \
        perl \
        libtool \
        libjansson-dev \
        libcurl4-openssl-dev \
        curl \
        zip \
        unzip \
        tar \
        patch \
        g++ \
        libipc-run-perl \
        jq \
        git \
        postgresql-server-dev-18 && \
    apt-get clean && \
    rm -rf /etc/apt/keyrings/pigsty.gpg \
        /etc/apt/sources.list.d/pigsty-io.list \
        /var/lib/apt/lists/* \
        /opt/vcpkg

# ========== 步骤 8: 安装运行时依赖 ==========
RUN set -ex; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libreadline8 \
        zlib1g \
        libxml2 \
        libxslt1.1 \
        libicu72 \
        libssl3 \
        libcurl4 \
        libgeos-3.11.0 \
        libproj25 \
        libgdal32 \
        libjson-c5 \
        libprotobuf-c1 \
        libossp-uuid16 \
        liblz4-1 \
        liblzma5 \
        libsnappy1v5 \
        libjansson4 \
        libbson-1.0-0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ========== 步骤 9: 配置扩展自动安装 ==========
RUN echo "#!/bin/bash\n\
set -e\n\
for db in template1 postgres; do\n\
  psql -v ON_ERROR_STOP=1 --username \"\$POSTGRES_USER\" \"\$db\" <<-EOSQL\n\
    CREATE EXTENSION IF NOT EXISTS bson;\n\
    CREATE EXTENSION IF NOT EXISTS pg_lake CASCADE;\n\
    CREATE EXTENSION IF NOT EXISTS vchord;\n\
    CREATE EXTENSION IF NOT EXISTS cron;\n\
    CREATE EXTENSION IF NOT EXISTS uint128;\n\
    CREATE EXTENSION IF NOT EXISTS mooncake;\n\
EOSQL\n\
done" > /docker-entrypoint-initdb.d/01-extensions.sh && \
    chmod +x /docker-entrypoint-initdb.d/01-extensions.sh

VOLUME ["/var/lib/postgresql/data"]
CMD ["postgres"]