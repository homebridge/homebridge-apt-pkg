ARG BASE_IMAGE
FROM ${BASE_IMAGE:-library/debian:bullseye}

ARG QEMU_ARCH
ENV QEMU_ARCH=${QEMU_ARCH:-x86_64} S6_KEEP_ENV=1

COPY build/qemu/qemu-${QEMU_ARCH}-static /usr/bin/

# Debian 11 (bullseye) is EOL and has been removed from deb.debian.org.
# Use the archive, and ignore its expired Release files. Remove when moving to bookworm.
RUN sed -i \
      -e 's|deb.debian.org/debian-security|archive.debian.org/debian-security|g' \
      -e 's|deb.debian.org/debian|archive.debian.org/debian|g' \
      -e '/bullseye-updates/d' \
      /etc/apt/sources.list && \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until && \
    apt-get update && \
    apt-get install -y build-essential debhelper dh-make devscripts jq git

WORKDIR /repo

CMD [ "/repo/build.sh" ]