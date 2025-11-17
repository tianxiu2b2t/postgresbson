FROM postgres:18-bookworm

# 第一步：安装构建依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg ca-certificates \
    git gcc g++ make patch \
    cmake ninja-build \
    flex bison perl libtool \
    zip unzip tar pkg-config autoconf automake \
    libreadline-dev zlib1g-dev libxml2-dev libxslt1-dev libicu-dev \
    libssl-dev libcurl4-openssl-dev \
    libgeos-dev libproj-dev libgdal-dev \
    libjson-c-dev libprotobuf-c-dev protobuf-c-compiler \
    uuid-dev libossp-uuid-dev \
    liblz4-dev liblzma-dev libsnappy-dev \
    libjansson-dev jq \
    libipc-run-perl \
    libbson-dev libbson-1.0-0 \
    postgresql-server-dev-18

# 第二步：安装 Pigsty 扩展
RUN curl -fsSL https://repo.pigsty.cc/key -o /tmp/pigsty-key && \
    gpg --dearmor -o /etc/apt/keyrings/pigsty.gpg /tmp/pigsty-key && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/infra generic main" > /etc/apt/sources.list.d/pigsty-io.list && \
    echo "deb [signed-by=/etc/apt/keyrings/pigsty.gpg] https://repo.pigsty.cc/apt/pgsql/bookworm bookworm main" >> /etc/apt/sources.list.d/pigsty-io.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-18-vchord \
        postgresql-18-cron \
        postgresql-18-pg-uint128 \
        postgresql-18-pg-mooncake

# 第三步：安装 vcpkg
RUN git clone https://github.com/microsoft/vcpkg.git /tmp/vcpkg && \
    /tmp/vcpkg/bootstrap-vcpkg.sh

# 第四步：更新 vcpkg 并安装依赖
RUN cd /tmp/vcpkg && git pull && ./vcpkg update && \
    /tmp/vcpkg/vcpkg install azure-identity-cpp azure-storage-blobs-cpp azure-storage-files-datalake-cpp openssl

ENV VCPKG_TOOLCHAIN_PATH=/tmp/vcpkg/scripts/buildsystems/vcpkg.cmake

# 第五步：编译安装 pg_lake (包含子模块)
RUN git clone --recurse-submodules https://github.com/Snowflake-Labs/pg_lake.git /tmp/pg_lake && \
    cd /tmp/pg_lake/duckdb_pglake && \
    make && make install && \
    cd /tmp/pg_lake && \
    make install-avro-local && \
    make fast && \
    make install-fast && \
    rm -rf /tmp/pg_lake

# 第六步：编译安装 postgresbson
RUN git clone https://github.com/buzzm/postgresbson.git /tmp/postgresbson && \
    sed -i 's|-I/root/projects/bson/include||g' /tmp/postgresbson/Makefile && \
    ln -sf /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so && \
    cd /tmp/postgresbson && \
    make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" CPPFLAGS="-I/usr/include/libbson-1.0" && \
    make install && \
    rm -rf /tmp/postgresbson

# 第七步：清理
RUN apt-get purge -y --auto-remove git gcc g++ make patch cmake ninja-build \
    flex bison perl libtool autoconf automake pkg-config \
    libbson-dev postgresql-server-dev-18 curl gnupg && \
    apt-get clean && \
    rm -rf /tmp/* /var/lib/apt/lists/* /etc/apt/sources.list.d/pigsty-io.list

# 数据目录
VOLUME ["/var/lib/postgresql/data"]

# 默认启动命令
CMD ["postgres"]
