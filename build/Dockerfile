ARG BASE_IMAGE
FROM ${BASE_IMAGE:-library/debian:bookworm}

ARG QEMU_ARCH
ENV QEMU_ARCH=${QEMU_ARCH:-x86_64}

# The build tools are not pinned to a version on purpose: the image follows Debian's security
# updates. curl and ca-certificates are for the Node.js download in build.sh.
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential debhelper devscripts jq git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /repo

CMD [ "/repo/build.sh" ]