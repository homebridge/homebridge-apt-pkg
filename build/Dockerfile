ARG BASE_IMAGE
FROM ${BASE_IMAGE:-library/debian:bookworm}

ARG QEMU_ARCH
ENV QEMU_ARCH=${QEMU_ARCH:-x86_64}

RUN apt-get update && \
    apt-get install -y build-essential debhelper devscripts jq git

WORKDIR /repo

CMD [ "/repo/build.sh" ]