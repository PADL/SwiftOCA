FROM arm64v8/ubuntu:latest AS base

ARG INSTALL_ZSH="true"
ARG UPGRADE_PACKAGES="false"

# Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN apt-get -q update
RUN apt-get -q install -y clang libicu-dev build-essential pkg-config curl sudo ca-certificates gnupg

FROM base as swift

RUN curl -fsSL https://archive.swiftlang.xyz/swiftlang_repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/swiftlang_repo.gpg.key
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/swiftlang_repo.gpg.key] https://archive.swiftlang.xyz/ubuntu/ jammy main" > /etc/apt/sources.list.d/swiftlang.list

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_INTERACTIVE_SEEN=true

RUN apt-get update
RUN apt-get install -y swiftlang

FROM swift AS build

COPY . /var/src
WORKDIR /var/src
RUN swift build

