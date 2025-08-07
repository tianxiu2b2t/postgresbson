FROM postgres:16

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone https://github.com/buzzm/postgresbson.git

WORKDIR /build/postgresbson

# 创建软链接以兼容 Makefile 的 -lbson.1
RUN ln -s /usr/lib/x86_64-linux-gnu/libbson-1.0.so /usr/lib/x86_64-linux-gnu/libbson.1.so

RUN make PG_CONFIG=$(which pg_config) CFLAGS="-I/usr/include/libbson-1.0" && \
    make install

RUN apt-get purge -y --auto-remove ca-certificates git gcc make libbson-dev postgresql-server-dev-16 && \
    rm -rf /build && \
    rm -rf /var/lib/apt/lists/*

VOLUME ["/var/lib/postgresql/data"]
CMD ["postgres"]
