FROM postgres:16

LABEL maintainer="yourname <youremail@example.com>"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone https://github.com/buzzm/postgresbson.git

WORKDIR /build/postgresbson

# 打印 pg_config 路径，便于调试
RUN which pg_config && pg_config --version

# 如果 make 继续报错，请将报错信息贴出来
RUN make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config

RUN make install

RUN apt-get purge -y --auto-remove ca-certificates git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /build/postgresbson && \
    rm -rf /var/lib/apt/lists/*

VOLUME ["/var/lib/postgresql/data"]
CMD ["postgres"]
