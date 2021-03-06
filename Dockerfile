FROM gcc AS buildtools
ARG release

# Update and install dependencies
RUN apt-get update
RUN apt-get -y --no-install-recommends install build-essential uuid-dev  acpica-tools git nasm

# Pull source
WORKDIR /root/src
RUN if [ ! -z $release ]; then git clone -b $release https://github.com/tianocore/edk2.git edk2; \
    else git clone https://github.com/tianocore/edk2.git edk2; fi

# Compile build tools
WORKDIR /root/src/edk2
RUN make -C BaseTools

# Setup environment
ENV EDK_TOOLS_PATH=/root/src/edk2/BaseTools
ENV EDK_BUILD_PATH=/root/src/edk2/Build

# OVMF Builder
# Build the OVMF for the emulator
FROM buildtools AS ovmfbuilder
WORKDIR /root/src/edk2

COPY ./misc/ovmf_target.txt ./Conf/target.txt
COPY ./script/build.sh ./
RUN ./build.sh

# Project Builder
# Build the project and generate the disk to boot from
FROM buildtools AS projectbuilder
WORKDIR /root/src/edk2

# Dependencies for create_iso
RUN apt-get -y --no-install-recommends install dosfstools mtools xorriso

COPY ./misc/uefibutt_target.txt ./Conf/target.txt
COPY ./script ./Uefibutt
COPY ./script/build.sh ./

RUN chmod +x ./build.sh ./Uefibutt/create_img.sh ./Uefibutt/create_iso.sh ./Uefibutt/postbuild.sh
COPY ./src ./Uefibutt
RUN ./build.sh

# Image Run
# Run built project image with QEMU
FROM alpine:latest as runimage
WORKDIR /root/
ENV EDK_BUILD_PATH=/root/src/edk2/Build

COPY --from=projectbuilder $EDK_BUILD_PATH/Uefibutt/RELEASE_GCC5/X64/Uefibutt.iso .
COPY --from=ovmfbuilder $EDK_BUILD_PATH/OvmfX64/RELEASE_GCC5/FV/ ./ovmf

# Replace the repository list in case it doesn't work
COPY ./misc/repositories.txt /etc/apk/repositories

# Setup QEMU
RUN apk update
RUN apk add qemu-system-x86_64

# Run with qemu
EXPOSE 5900
RUN qemu-system-x86_64 -L ./ovmf -bios ./ovmf/OVMF.fd -cdrom ./Uefibutt.iso -vnc 172.17.0.2:0
