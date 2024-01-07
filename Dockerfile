FROM golang:1.17.8-buster AS builder

ARG LIBPOSTAL_UPSTREAM
ENV LIBPOSTAL_UPSTREAM ${LIBPOSTAL_UPSTREAM:-github.com/openvenues/libpostal}

ARG LIBPOSTAL_REST_UPSTREAM
ENV LIBPOSTAL_REST_UPSTREAM ${LIBPOSTAL_REST_UPSTREAM:-github.com/johnlonganecker/libpostal-rest}

ARG LIBPOSTAL_COMMIT
ENV LIBPOSTAL_COMMIT ${LIBPOSTAL_COMMIT:-master}

ARG LIBPOSTAL_REST_RELEASE
ENV LIBPOSTAL_REST_RELEASE ${LIBPOSTAL_REST_RELEASE:-1.1.0}

ENV DEBIAN_FRONTEND noninteractive

ARG CONFIGURE_FLAGS
ENV CONFIGURE_FLAGS ${CONFIGURE_FLAGS:--disable-sse2}

RUN set -eux; \
    apt-get update;  \
    apt-get install -y --no-install-recommends \
        build-essential \
        libsnappy-dev \
        pkg-config \
        autoconf \
        automake \
        libtool \
        curl \
        git \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    git clone \
        "https://${LIBPOSTAL_UPSTREAM}" \
        --branch "${LIBPOSTAL_COMMIT}" \
        --depth=1 \
        --single-branch \
        /usr/src/libpostal \
    ; \
    cd /usr/src/libpostal; \
    ./bootstrap.sh; \
    mkdir --parents /opt/libpostal_data; \
    ./configure --datadir=/opt/data --prefix=/libpostal ${CONFIGURE_FLAGS}; \
    make --jobs=$(nproc); \
    make install DESTDIR=/libpostal; \
    ldconfig -v

RUN set -eux; \
    mv /libpostal /_libpostal; \
    mv /_libpostal/libpostal /libpostal; \
    cd /libpostal; \
    export GOPATH=/usr/src/libpostal/workspace; \
    export PKG_CONFIG_PATH=/usr/src/libpostal; \
    pkg-config --cflags libpostal; \
    go install "${LIBPOSTAL_REST_UPSTREAM}@v${LIBPOSTAL_REST_RELEASE}"; \
    mv /usr/src/libpostal/workspace /libpostal/workspace; \
    chmod a+x /libpostal/bin/* /libpostal/workspace/bin/*; \
    rm -rf /usr/src/libpostal

FROM busybox:glibc
WORKDIR /libpostal

ARG LOG_LEVEL
ENV LOG_LEVEL "${LOG_LEVEL:-info}"

ARG LOG_STRUCTURED
ENV LOG_STRUCTURED "${LOG_STRUCTURED:-true}"

ARG PROMETHEUS_ENABLED
ENV PROMETHEUS_ENABLED "${PROMETHEUS_ENABLED:-true}"

ARG PROMETHEUS_PORT
ENV PROMETHEUS_PORT "${PROMETHEUS_PORT:-9090}"

ARG LISTEN_PORT
ENV LISTEN_PORT "${LISTEN_PORT:-8080}"

COPY --from=builder /libpostal/bin/* /usr/bin/
COPY --from=builder /libpostal/workspace/bin/* /usr/bin/
COPY --from=builder /libpostal/lib/* /usr/lib/
COPY --from=builder /libpostal/include/* /usr/lib/
COPY --from=builder /opt/data /opt/data

EXPOSE 8080/tcp
EXPOSE 8090/tcp
CMD ["/usr/bin/libpostal-rest"]
