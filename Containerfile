# Two images from one file, picked with `podman build --target driftwm|gnome` (see Justfile)

# Fedora major must match the bases below, so driftwm links against the same libs
ARG FEDORA_VERSION=44
# Pinned driftwm release; bump tag and commit together on purpose
ARG DRIFTWM_VERSION=v0.21.0
ARG DRIFTWM_COMMIT=df3de27b26c7998e8a460cffd8a4925cbed3a322

# driftwm is not packaged for Fedora: build it from a release tag
FROM quay.io/fedora/fedora:${FEDORA_VERSION} AS driftwm-build
ARG DRIFTWM_VERSION
ARG DRIFTWM_COMMIT
RUN dnf5 -y install git make cargo rust pkgconf-pkg-config \
        libseat-devel libdisplay-info-devel libinput-devel mesa-libgbm-devel libxkbcommon-devel systemd-devel && \
    git clone --depth 1 --branch "$DRIFTWM_VERSION" https://github.com/malbiruk/driftwm.git /src && \
    test "$(git -C /src rev-parse HEAD)" = "$DRIFTWM_COMMIT" && \
    cd /src && make build && make install DESTDIR=/out PREFIX=/usr && \
    cp -r extras /out/usr/share/driftwm/extras

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

### driftwm: Universal Blue base (Fedora Atomic without a desktop, codecs and full Mesa included)
FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION} AS driftwm

# Changes whenever build_files/ or system_files/ change. buildah does not always
# invalidate the bind-mounted ctx stage on its own, so the Justfile passes a hash.
ARG BUILD_FILES_SHA=0

COPY --from=driftwm-build /out/ /

# Vendor RPMs (Happ, PdfCraft) install into /opt; on bootc it is /var/opt and gets lost on deploy
RUN rm /opt && mkdir /opt

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    VARIANT=driftwm bash /ctx/build.sh

RUN bootc container lint

### gnome: Universal Blue Silverblue (stock GNOME + GDM, codecs and full Mesa included)
FROM ghcr.io/ublue-os/silverblue-main:${FEDORA_VERSION} AS gnome

# See the driftwm stage: forces cache invalidation when build_files/system_files change
ARG BUILD_FILES_SHA=0

RUN rm /opt && mkdir /opt

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    VARIANT=gnome bash /ctx/build.sh

RUN bootc container lint
