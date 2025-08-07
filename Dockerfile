FROM postgres:16

LABEL maintainer="yourname <youremail@example.com>"

# 安装构建依赖和 CA 证书
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 克隆 postgresbson 源码
RUN git clone https://github.com/buzzm/postgresbson.git

WORKDIR /build/postgresbson

# 编译并安装扩展（指定 libbson 头文件路径）
RUN make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" && \
    make install

# 清理构建依赖和源码，减小镜像体积
RUN apt-get purge -y --auto-remove ca-certificates git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /build && \
    rm -rf /var/lib/apt/lists/*

# 设置数据卷
VOLUME ["/var/lib/postgresql/data"]

# 默认启动 postgres
CMD ["postgres"]
