# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

################################################################################
ARG PARENT_IMAGE=ubuntu:24.04
FROM ${PARENT_IMAGE} AS build

USER root
WORKDIR /tmp/

RUN <<EOR
apt-get -qq update
# For: Slurm DEB build
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --no-install-recommends \
  build-essential fakeroot devscripts equivs
# For: ./scripts/
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --no-install-recommends \
  curl jq
apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

COPY scripts/ /tmp/scripts/
COPY patches/ /tmp/patches/

# Ref: https://slurm.schedmd.com/quickstart_admin.html#debuild
ARG SLURM_VERSION="24.05"
RUN <<EOR
apt-get -qq update
/tmp/scripts/download-slurm.sh ${SLURM_VERSION}
/tmp/scripts/patch-slurm.sh /tmp/patches /tmp/slurm
mk-build-deps -ir --tool='apt-get -qq -y -o Debug::pkgProblemResolver=yes --no-install-recommends' /tmp/slurm/debian/control
( cd /tmp/slurm/ && debuild -b -uc -us >/dev/null )
apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

RUN /tmp/scripts/install-kubectl.sh

# OCI Annotations
# https://github.com/opencontainers/image-spec/blob/v1.0/annotations.md
LABEL org.opencontainers.image.authors="slinky@schedmd.com" \
      org.opencontainers.image.base.name="${PARENT_IMAGE}" \
      org.opencontainers.image.documentation="https://slurm.schedmd.com/documentation.html" \
      org.opencontainers.image.license="GPL-2.0+" \
      org.opencontainers.image.vendor="SchedMD LLC." \
      org.opencontainers.image.version="${SLURM_VERSION}" \
      org.opencontainers.image.source="https://github.com/SlinkyProject/containers"

# HasRequiredLabel requirement from Red Hat OpenShift Software Certification
# https://access.redhat.com/documentation/en-us/red_hat_software_certification/2024/html/red_hat_openshift_software_certification_policy_guide/assembly-requirements-for-container-images_openshift-sw-cert-policy-introduction#con-image-metadata-requirements_openshift-sw-cert-policy-container-images
LABEL vendor="SchedMD LLC." \
      version="${SLURM_VERSION}" \
      release="https://github.com/SlinkyProject/containers"

################################################################################
FROM ${PARENT_IMAGE} AS base

USER root
WORKDIR /tmp/

ARG SLURM_USER=slurm
ARG SLURM_USER_UID=401
ARG SLURM_USER_GID=401
RUN <<EOR
groupadd --system --gid=${SLURM_USER_GID} ${SLURM_USER}
useradd --system --no-log-init --uid=${SLURM_USER_UID} --gid=${SLURM_USER_GID} --shell=/usr/sbin/nologin ${SLURM_USER}
EOR

## START DEBUG SECTION ###
ARG DEBUG=0
RUN <<EOR
# For: Development and Debugging
if [ "$DEBUG" = true ] || [ "$DEBUG" = 1 ]; then
  apt-get -qq update
  DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --no-install-recommends sudo
  echo "${SLURM_USER} ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/slurm
  apt-get clean && rm -rf /var/lib/apt/lists/*
fi
EOR
### END DEBUG SECTION ###

# Ref: https://slurm.schedmd.com/quickstart_admin.html#debinstall
COPY --from=build /tmp/*.deb /tmp/

RUN <<EOR
apt-get -qq update
# For: Helm Chart
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --no-install-recommends \
  rsync gettext-base iputils-ping
apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

COPY --from=build /usr/local/bin/kubectl /usr/local/bin/kubectl

################################################################################
# SLURM: slurmctld
# BUILD: `docker build --target=slurmctld -t [<reg>/]<name>:<tag> .`
################################################################################
FROM base AS slurmctld

# OCI Annotations
# https://github.com/opencontainers/image-spec/blob/v1.0/annotations.md
LABEL org.opencontainers.image.title="Slurm Control Plane" \
      org.opencontainers.image.description="slurmctld - The central management daemon of Slurm" \
      org.opencontainers.image.documentation="https://slurm.schedmd.com/slurmctld.html"

# HasRequiredLabel requirement from Red Hat OpenShift Software Certification
# https://access.redhat.com/documentation/en-us/red_hat_software_certification/2024/html/red_hat_openshift_software_certification_policy_guide/assembly-requirements-for-container-images_openshift-sw-cert-policy-introduction#con-image-metadata-requirements_openshift-sw-cert-policy-container-images
LABEL name="Slurm Control Plane" \
      summary="slurmctld - The central management daemon of Slurm" \
      description="slurmctld - The central management daemon of Slurm"

USER root
WORKDIR /tmp/

RUN <<EOR
apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --fix-broken \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-dev_[0-9]*.deb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-slurmctld_[0-9]*.deb \
  ./slurm-smd_[0-9]*.deb
rm *.deb && apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

ENTRYPOINT ["slurmctld"]
CMD ["-D"]

################################################################################
# SLURM: slurmd
# BUILD: `docker build --target=slurmd -t [<reg>/]<name>:<tag> .`
################################################################################
FROM base AS slurmd

# OCI Annotations
# https://github.com/opencontainers/image-spec/blob/v1.0/annotations.md
LABEL org.opencontainers.image.title="Slurm Worker Agent" \
      org.opencontainers.image.description="slurmd - The compute node daemon for Slurm" \
      org.opencontainers.image.documentation="https://slurm.schedmd.com/slurmd.html"

# HasRequiredLabel requirement from Red Hat OpenShift Software Certification
# https://access.redhat.com/documentation/en-us/red_hat_software_certification/2024/html/red_hat_openshift_software_certification_policy_guide/assembly-requirements-for-container-images_openshift-sw-cert-policy-introduction#con-image-metadata-requirements_openshift-sw-cert-policy-container-images
LABEL name="Slurm Worker Agent" \
      summary="slurmd - The compute node daemon for Slurm" \
      description="slurmd - The compute node daemon for Slurm"

USER root
WORKDIR /tmp/

RUN <<EOR
apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --fix-broken \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-dev_[0-9]*.deb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-libnss-slurm_[0-9]*.deb \
  ./slurm-smd-libpam-slurm-adopt_[0-9]*.deb \
  ./slurm-smd-libpmi2-0_[0-9]*.deb \
  ./slurm-smd-slurmd_[0-9]*.deb \
  ./slurm-smd_[0-9]*.deb
rm *.deb && apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

ENTRYPOINT ["slurmd"]
CMD ["-D"]

################################################################################
# SLURM: slurmdbd
# BUILD: `docker build --target=slurmdbd -t [<reg>/]<name>:<tag> .`
################################################################################
FROM base AS slurmdbd

# OCI Annotations
# https://github.com/opencontainers/image-spec/blob/v1.0/annotations.md
LABEL org.opencontainers.image.title="Slurm Database Agent" \
      org.opencontainers.image.description="slurmdbd - Slurm Database Daemon" \
      org.opencontainers.image.documentation="https://slurm.schedmd.com/slurmdbd.html"

# HasRequiredLabel requirement from Red Hat OpenShift Software Certification
# https://access.redhat.com/documentation/en-us/red_hat_software_certification/2024/html/red_hat_openshift_software_certification_policy_guide/assembly-requirements-for-container-images_openshift-sw-cert-policy-introduction#con-image-metadata-requirements_openshift-sw-cert-policy-container-images
LABEL name="Slurm Database Agent" \
      summary="slurmdbd - Slurm Database Daemon" \
      description="slurmdbd - Slurm Database Daemon"

USER root
WORKDIR /tmp/

RUN <<EOR
apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --fix-broken \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-slurmdbd_[0-9]*.deb \
  ./slurm-smd_[0-9]*.deb
rm *.deb && apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

ENTRYPOINT ["slurmdbd"]
CMD ["-D"]

################################################################################
# SLURM: slurmrestd
# BUILD: `docker build --target=slurmrestd -t [<reg>/]<name>:<tag> .`
################################################################################
FROM base AS slurmrestd

# OCI Annotations
# https://github.com/opencontainers/image-spec/blob/v1.0/annotations.md
LABEL org.opencontainers.image.title="Slurm REST API Agent" \
      org.opencontainers.image.description="slurmrestd - Interface to Slurm via REST API" \
      org.opencontainers.image.documentation="https://slurm.schedmd.com/slurmrestd.html"

# HasRequiredLabel requirement from Red Hat OpenShift Software Certification
# https://access.redhat.com/documentation/en-us/red_hat_software_certification/2024/html/red_hat_openshift_software_certification_policy_guide/assembly-requirements-for-container-images_openshift-sw-cert-policy-introduction#con-image-metadata-requirements_openshift-sw-cert-policy-container-images
LABEL name="Slurm REST API Agent" \
      summary="slurmrestd - Interface to Slurm via REST API" \
      description="slurmrestd - Interface to Slurm via REST API"

USER root
WORKDIR /tmp/

RUN <<EOR
apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --fix-broken \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-slurmrestd_[0-9]*.deb \
  ./slurm-smd_[0-9]*.deb
rm *.deb && apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

ENTRYPOINT ["slurmrestd"]
CMD ["0.0.0.0:6820"]

################################################################################
# SLURM: sackd
# BUILD: `docker build --target=sackd -t [<reg>/]<name>:<tag> .`
################################################################################
FROM base AS sackd

# OCI Annotations
# https://github.com/opencontainers/image-spec/blob/v1.0/annotations.md
LABEL org.opencontainers.image.title="Slurm Auth/Cred Server" \
      org.opencontainers.image.description="sackd - Slurm Auth and Cred Kiosk Daemon" \
      org.opencontainers.image.documentation="https://slurm.schedmd.com/sackd.html"

# HasRequiredLabel requirement from Red Hat OpenShift Software Certification
# https://access.redhat.com/documentation/en-us/red_hat_software_certification/2024/html/red_hat_openshift_software_certification_policy_guide/assembly-requirements-for-container-images_openshift-sw-cert-policy-introduction#con-image-metadata-requirements_openshift-sw-cert-policy-container-images
LABEL name="Slurm Auth/Cred Server" \
      summary="sackd - Slurm Auth and Cred Kiosk Daemon" \
      description="sackd - Slurm Auth and Cred Kiosk Daemon"

USER root
WORKDIR /tmp/

RUN <<EOR
apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --fix-broken \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-sackd_[0-9]*.deb \
  ./slurm-smd_[0-9]*.deb
rm *.deb && apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

ENTRYPOINT ["sackd"]

################################################################################
# SLURM: slurm
# BUILD: `docker build --target=slurm -t [<reg>/]<name>:<tag> .`
################################################################################
FROM base AS slurm

# OCI Annotations
# https://github.com/opencontainers/image-spec/blob/v1.0/annotations.md
LABEL org.opencontainers.image.title="Slurm" \
      org.opencontainers.image.description="Contains all Slurm daemons" \
      org.opencontainers.image.documentation="https://slurm.schedmd.com/documentation.html"

# HasRequiredLabel requirement from Red Hat OpenShift Software Certification
# https://access.redhat.com/documentation/en-us/red_hat_software_certification/2024/html/red_hat_openshift_software_certification_policy_guide/assembly-requirements-for-container-images_openshift-sw-cert-policy-introduction#con-image-metadata-requirements_openshift-sw-cert-policy-container-images
LABEL name="Slurm" \
      summary="Contains all Slurm daemons" \
      description="Contains all Slurm daemons"

USER root
WORKDIR /tmp/

RUN <<EOR
apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get -qq -y install --fix-broken \
  ./slurm-smd-client_[0-9]*.deb \
  ./slurm-smd-dev_[0-9]*.deb \
  ./slurm-smd-doc_[0-9]*.deb \
  ./slurm-smd-libnss-slurm_[0-9]*.deb \
  ./slurm-smd-libpam-slurm-adopt_[0-9]*.deb \
  ./slurm-smd-libpmi2-0_[0-9]*.deb \
  ./slurm-smd-sackd_[0-9]*.deb \
  ./slurm-smd-slurmctld_[0-9]*.deb \
  ./slurm-smd-slurmd_[0-9]*.deb \
  ./slurm-smd-slurmdbd_[0-9]*.deb \
  ./slurm-smd-slurmrestd_[0-9]*.deb \
  ./slurm-smd_[0-9]*.deb
rm *.deb && apt-get clean && rm -rf /var/lib/apt/lists/*
EOR

CMD ["bash", "--login"]
