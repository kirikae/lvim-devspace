FROM alpine:3.24 AS builder

RUN apk add --no-cache \
    build-base \
    automake \
    autoconf \
    pkgconfig \
    bison \
    curl \
    ncurses-dev \
    ncurses-static \
    libevent-dev \
    libevent-static

ARG TMUX_VERSION=3.7c
RUN mkdir -p /out \
 && curl -fsSL "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz" -o /tmp/tmux.tar.gz \
 && tar -xzf /tmp/tmux.tar.gz -C /tmp \
 && cd "/tmp/tmux-${TMUX_VERSION}" \
 && ./configure --enable-static LDFLAGS="-static" \
 && make -j"$(nproc)" \
 && strip tmux \
 && cp tmux /out/tmux

ARG TTYD_VERSION=1.7.7
RUN ARCH="$(uname -m)" \
 && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${ARCH}" -o /out/ttyd \
 && chmod +x /out/ttyd

FROM alpine:3.24
COPY --from=builder /out/tmux /out/ttyd /opt/toolbox/
COPY tmux.conf.default /opt/toolbox/tmux.conf.default
COPY entrypoint-volume.sh /opt/toolbox/entrypoint-volume.sh
COPY entrypoint-init-container.sh /entrypoint-init-container.sh
RUN chmod +x /opt/toolbox/tmux /opt/toolbox/ttyd /opt/toolbox/entrypoint-volume.sh /entrypoint-init-container.sh
ENTRYPOINT ["/entrypoint-init-container.sh"]
