FROM node:10.15.1-stretch-slim

LABEL maintainer "https://github.com/blacktop"

RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  bzip2 \
  unzip \
  xz-utils \
  && rm -rf /var/lib/apt/lists/*

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
  echo '#!/bin/sh'; \
  echo 'set -e'; \
  echo; \
  echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
  } > /usr/local/bin/docker-java-home \
  && chmod +x /usr/local/bin/docker-java-home

# do some fancy footwork to create a JAVA_HOME that's cross-architecture-safe
RUN ln -svT "/usr/lib/jvm/java-8-openjdk-$(dpkg --print-architecture)" /docker-java-home
ENV JAVA_HOME /docker-java-home/jre

ENV JAVA_VERSION 8u181
ENV JAVA_DEBIAN_VERSION 8u181-b13-2~deb9u1

RUN set -ex; \
  \
  # deal with slim variants not having man page directories (which causes "update-alternatives" to fail)
  if [ ! -d /usr/share/man/man1 ]; then \
  mkdir -p /usr/share/man/man1; \
  fi; \
  \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  openjdk-8-jre="$JAVA_DEBIAN_VERSION" \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  \
  # verify that "docker-java-home" returns what we expect
  [ "$(readlink -f "$JAVA_HOME")" = "$(docker-java-home)" ]; \
  \
  # update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
  update-alternatives --get-selections | awk -v home="$(readlink -f "$JAVA_HOME")" 'index($3, home) == 1 { $2 = "manual"; print | "update-alternatives --set-selections" }'; \
  # ... and verify that it actually worked for one of the alternatives we care about
  update-alternatives --query java | grep -q 'Status: manual'

ENV PATH=${PATH}:${JAVA_HOME}/bin:/plugin/kibana/bin:${PATH}

ARG VERSION=6.6.1

COPY node-prune.sh /usr/bin/node-prune
RUN echo "===> Installing elasticdump" \
  && set -ex \
  && yarn global add elasticdump \
  && cd /usr/local/lib/ && node-prune || true

WORKDIR /plugin

RUN echo "===> Cloning Kibana v$VERSION" \
  && git clone --depth 1 -b v${VERSION} https://github.com/elastic/kibana.git

WORKDIR /plugin/kibana

# Install kibana node_modules
RUN set -ex \
  && yarn kbn bootstrap \
  && cd /usr/local/lib \
  && node-prune || true \
  && chown -R node:node /plugin

COPY entrypoint.sh /entrypoint.sh
RUN chown node:node /entrypoint.sh

USER node

EXPOSE 5601 9200

ENTRYPOINT ["/entrypoint.sh"]
