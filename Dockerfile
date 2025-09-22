# syntax=docker/dockerfile:1
FROM debian:bookworm AS builder
ARG LIBPOSTAL_UPSTREAM=github.com/openvenues/libpostal
ENV LIBPOSTAL_UPSTREAM=${LIBPOSTAL_UPSTREAM}
ARG LIBPOSTAL_COMMIT=master
ENV LIBPOSTAL_COMMIT=${LIBPOSTAL_COMMIT}
ENV DEBIAN_FRONTEND=noninteractive
ENV PKG_CONFIG_PATH=/libpostal

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOF
    set -eux
    apt-get update
    apt-get install \
        --yes \
        --no-install-recommends \
      build-essential \
      ca-certificates \
      libsnappy-dev \
      pkg-config \
      autoconf \
      automake \
      libtool \
      curl \
      git \
    ;
    rm -rf /var/lib/apt/lists/*
    git clone \
        "https://${LIBPOSTAL_UPSTREAM}" \
        --branch "${LIBPOSTAL_COMMIT}" \
        --depth=1 \
        --single-branch \
      /usr/src/libpostal

    cd /usr/src/libpostal
    ./bootstrap.sh
    mkdir --parents /opt/data
    ./configure --datadir=/opt/data --prefix=/libpostal
    make --jobs=$(nproc)
    make install DESTDIR=/libpostal
EOF

RUN <<EOF
    set -eux
    mv /libpostal/libpostal/* /libpostal/
    rm -rf /libpostal/libpostal
    mkdir /libpostal/bin/.libs
    cd /usr/src/libpostal
    cp libpostal.pc /libpostal/
    cp src/.libs/libpostal src/.libs/address_parser /libpostal/bin/
    chmod a+x /libpostal/bin/*
    cd /libpostal
    ldconfig -v
    pkg-config --cflags libpostal
EOF

FROM debian:bookworm-slim AS library
COPY --link --from=builder /libpostal/bin/* /usr/bin/
COPY --link --from=builder /libpostal/lib/* /usr/lib/
COPY --link --from=builder /libpostal/include/* /usr/lib/
COPY --link --from=builder /opt/data /opt/data
COPY --link --chmod=0555 <<EOF /entrypoint.sh
#!/usr/bin/env bash
exec "\${@}"
EOF

ENTRYPOINT ["/entrypoint.sh"]
CMD ["libpostal", "--help"]

FROM golang:1.25-bookworm  AS api_builder
ARG LIBPOSTAL_REST_UPSTREAM=github.com/johnlonganecker/libpostal-rest
ENV LIBPOSTAL_REST_UPSTREAM=${LIBPOSTAL_REST_UPSTREAM}
ARG LIBPOSTAL_REST_VERSION=1.1.0
ENV LIBPOSTAL_REST_VERSION=${LIBPOSTAL_REST_VERSION}
ENV PKG_CONFIG_PATH=/libpostal
ENV GOPATH=/go

WORKDIR /libpostal

COPY --link --from=builder /libpostal /libpostal

RUN --mount=type=cache,id=go-mod,target=/go/pkg/mod \
    --mount=type=cache,id=go-build,target=/root/.cache/go-build <<EOF
    set -eux
    go install "${LIBPOSTAL_REST_UPSTREAM}@v${LIBPOSTAL_REST_VERSION}"
    mv /go/bin/* /libpostal/bin/
    chmod a+x /libpostal/bin/*
EOF

FROM busybox:glibc AS api
ARG LOG_LEVEL=info
ENV LOG_LEVEL=${LOG_LEVEL}
ARG LOG_STRUCTURED=true
ENV LOG_STRUCTURED=${LOG_STRUCTURED}
ARG PROMETHEUS_ENABLED=true
ENV PROMETHEUS_ENABLED=${PROMETHEUS_ENABLED}
ARG PROMETHEUS_PORT=9090
ENV PROMETHEUS_PORT=${PROMETHEUS_PORT}
ARG LISTEN_PORT=8080
ENV LISTEN_PORT=${LISTEN_PORT}

WORKDIR /libpostal

COPY --link --from=api_builder /libpostal/bin/* /usr/bin/
COPY --link --from=builder /libpostal/bin/* /usr/bin/
COPY --link --from=builder /libpostal/lib/* /usr/lib/
COPY --link --from=builder /libpostal/include/* /usr/include/
COPY --link --from=builder /opt/data /opt/data

EXPOSE ${LISTEN_PORT}/tcp
EXPOSE ${PROMETHEUS_PORT}/tcp
CMD ["/usr/bin/libpostal-rest"]
