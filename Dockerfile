FROM colemancda/swift-armv7:latest-prebuilt AS build

ARG INSTALL_ZSH="true"
ARG UPGRADE_PACKAGES="false"

# Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

COPY . /var/src
WORKDIR /usr/src/swift-armv7

RUN swift --version

ARG SWIFT_PACKAGE_SRCDIR=/var/src
ARG SWIFT_PACKAGE_BUILDDIR=$SWIFT_PACKAGE_SRCDIR/.build

RUN mkdir -p $SWIFT_PACKAGE_BUILDDIR
RUN ./generate-swiftpm-toolchain.sh
RUN ./build-swift-package.sh

