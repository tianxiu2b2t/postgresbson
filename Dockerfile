FROM postgres:16

# 安装构建依赖+CA证书
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /var/lib/apt/lists/*

# 安装构建依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /var/lib/apt/lists/*

# 拉取并编译 postgresbson，加重试机制，避免偶发网络错误
WORKDIR /build
RUN for i in 1 2 3; do \
      git clone https://github.com/buzzm/postgresbson.git && break || sleep 10; \
    done && \
    cd postgresbson && \
    make && \
    make install

# 清理构建依赖和源码（可选，生产环境建议开启）
RUN apt-get purge -y --auto-remove git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /build/postgresbson && \
    rm -rf /var/lib/apt/lists/*

# 创建测试数据目录等（可选）
VOLUME ["/var/lib/postgresql/data"]

# 默认启动 postgres
CMD ["postgres"]
