FROM postgres:16

LABEL maintainer="yourname <youremail@example.com>"

# 安装构建依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /var/lib/apt/lists/*

# 拉取并编译 postgresbson
WORKDIR /build
RUN git clone https://github.com/buzzm/postgresbson.git && \
    cd postgresbson && \
    make && \
    make install

# 清理构建依赖和源码（可选，生产环境建议开启）
RUN apt-get purge -y --auto-remove git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /build/postgresbson

# 创建测试数据目录等（可选）
VOLUME ["/var/lib/postgresql/data"]

# 默认启动 postgres
CMD ["postgres"]
