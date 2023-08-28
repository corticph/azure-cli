#---------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

ARG PYTHON_VERSION="3.11"

FROM corti.azurecr.io/base/python:${PYTHON_VERSION}-alpine3

ARG CLI_VERSION
ARG WORKDIR=/opt/corti
ARG USER=corti
ARG USER_ID=1001

# bash gcc make openssl-dev libffi-dev musl-dev - dependencies required for CLI
# openssh - included for ssh-keygen
# ca-certificates

# curl - required for installing jp
# jq - we include jq as a useful tool
# pip wheel - required for CLI packaging
# jmespath-terminal - we include jpterm as a useful tool
# libintl and icu-libs - required by azure devops artifact (az extension add --name azure-devops)

# We don't use openssl (3.0) for now. We only install it so that users can use it.
RUN apk add --no-cache bash openssh ca-certificates jq curl openssl perl git zip shadow \
 && apk add --no-cache --virtual .build-deps gcc make openssl-dev libffi-dev musl-dev linux-headers \
 && apk add --no-cache libintl icu-libs libc6-compat \
 && apk add --no-cache bash-completion \
 && update-ca-certificates \
 && mkdir -p ${WORKDIR} \
 && groupadd -g ${USER_ID} ${USER} \
 && useradd -u ${USER_ID} -g ${USER} -rMd ${WORKDIR} ${USER} \
 && chown -R ${USER}:${USER} ${WORKDIR}

ARG JP_VERSION="0.1.3"

RUN curl -L https://github.com/jmespath/jp/releases/download/${JP_VERSION}/jp-linux-amd64 -o /usr/local/bin/jp \
 && chmod +x /usr/local/bin/jp

WORKDIR azure-cli
COPY . /azure-cli

# 1. Build packages and store in tmp dir
# 2. Install the cli and the other command modules that weren't included
RUN ./scripts/install_full.sh && python ./scripts/trim_sdk.py \
 && cat /azure-cli/az.completion > ~/.bashrc \
 && runDeps="$( \
    scanelf --needed --nobanner --recursive /usr/local \
        | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
        | sort -u \
        | xargs -r apk info --installed \
        | sort -u \
    )" \
 && apk add --virtual .rundeps $runDeps

WORKDIR /

# Remove CLI source code from the final image and normalize line endings.
RUN rm -rf ./azure-cli && \
    dos2unix /root/.bashrc /usr/local/bin/az

WORKDIR ${WORKDIR}
USER ${USER}

ENV AZ_INSTALLER=DOCKER
CMD bash
