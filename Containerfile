# Two images from one file, picked with `podman build --target driftwm|gnome` (see Justfile)

# Fedora major must match the bases below, so driftwm links against the same libs
ARG FEDORA_VERSION=44
# Empty = latest release tag; set e.g. v0.21.0 to pin when a new release breaks
ARG DRIFTWM_VERSION=

# driftwm is not packaged for Fedora: build it from a release tag
FROM quay.io/fedora/fedora:${FEDORA_VERSION} AS driftwm-build
ARG DRIFTWM_VERSION
RUN dnf5 -y install git make cargo rust pkgconf-pkg-config \
        libseat-devel libdisplay-info-devel libinput-devel mesa-libgbm-devel libxkbcommon-devel systemd-devel && \
    TAG="${DRIFTWM_VERSION:-$(git ls-remote --tags --refs --sort=-v:refname https://github.com/malbiruk/driftwm.git 'v*' | head -1 | sed 's#.*/##')}" && \
    git clone --depth 1 --branch "$TAG" https://github.com/malbiruk/driftwm.git /src && \
    cd /src && make build && make install DESTDIR=/out PREFIX=/usr

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

### driftwm: Universal Blue base (Fedora Atomic without a desktop, codecs and full Mesa included)
FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION} AS driftwm

COPY --from=driftwm-build /out/ /

# Vendor RPMs (Happ, RuDesktop...) install into /opt; on bootc it is /var/opt and gets lost on deploy
RUN rm /opt && mkdir /opt

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    VARIANT=driftwm bash /ctx/build.sh

RUN bootc container lint

### gnome: Universal Blue Silverblue (stock GNOME + GDM, codecs and full Mesa included)
FROM ghcr.io/ublue-os/silverblue-main:${FEDORA_VERSION} AS gnome

RUN rm /opt && mkdir /opt

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    VARIANT=gnome bash /ctx/build.sh

RUN bootc container lint
