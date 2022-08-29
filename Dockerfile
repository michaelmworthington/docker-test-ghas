# syntax=docker/dockerfile:1.3-labs
# https://jedevc.com/blog/dockerfile-heredocs-intro/

# PDI is supported on JDK 8
# This will run the most recent JDK on top of a slimed version of Debian 11 (Bullseye)
# TODO: best practice to pin the sha of the tag - how do we keep up to date???
#FROM openjdk:8u332-jre-slim-bullseye
#docker pull 
FROM openjdk:8u332-jre-slim-bullseye@sha256:704f379deb0f0894681470ec491c5254e7c4894ddc01e6d8823cfe8a2723b458
#docker hub - amd
#FROM openjdk:8u332-jre-slim-bullseye@sha256:7aa0997564df6b46ac70db0d75b0f4bf3c62dd1bc0ed8fc0953ec6c569b4a657
#docker hub - arm
#FROM openjdk:8u332-jre-slim-bullseye@sha256:64a800eeac81c35c8377df53a9470bec75c069e19a7a374904266206da495df8

ARG GITHUB_REPOSITORY
ARG GITHUB_REF_NAME
ARG GITHUB_RUN_ID
ARG GITHUB_RUN_NUMBER
ARG GITHUB_SHA

# HereDoc force immediate exit upon command failure
# https://jedevc.com/blog/dockerfile-heredocs-intro/
SHELL ["/bin/sh", "-e", "-c"]

# Create a non-root user (looks like consensus is that it is bad to specify the GID and UID)
#     https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#user
RUN <<EOF
groupadd --system pdi
useradd --gid pdi --no-log-init --create-home --system pdi
EOF

# Install OS packages
#     TODO: Best Practice to pin versions - how to we keep up to date?????
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends wget=1.21-1+deb11u1
apt-get install -y --no-install-recommends dos2unix=7.4.1-1
apt-get install -y --no-install-recommends unzip=6.0-26
apt-get install -y --no-install-recommends gettext=0.21-4

# For the XLS Templates (libfreetype6 still resulted in a null pointer. fontconfig has libfreetype6 as a dependency so they both get installed)
#   see: https://github.com/docker-library/openjdk/issues/333
#   apt-get install -y --no-install-recommends libfreetype6=2.10.4+dfsg-1 \
apt-get install -y --no-install-recommends fontconfig=2.13.1-4.2

# for running pdi with a different user id
apt-get install -y --no-install-recommends gosu=1.12-1+b6

# Clean Up
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Install Pentaho
ENV PDI_VERSION=7.1 PDI_BUILD=7.1.0.0-12
# TODO: store binaries in GitHub Artifacts since Sourceforge is slow
# TODO: Should we switch the order of PDI install and APT GET so a rebuild doesn't trigger a new PDI Layer?
RUN <<EOF
mkdir /opt/pentaho
cd /opt/pentaho
touch pdi-ce-${PDI_BUILD}
# wget --progress=dot:giga http://host.docker.internal:8001/files/pdi-ce-${PDI_BUILD}.zip
wget --progress=dot:giga http://downloads.sourceforge.net/project/pentaho/Data%20Integration/${PDI_VERSION}/pdi-ce-${PDI_BUILD}.zip
unzip -q ./*.zip
rm -- *.zip

# Remove all the extra plugins (i.e. server mode)
cd /opt/pentaho/data-integration/plugins
rm -rf -- VerticaBulkLoader elasticsearch-bulk-insert-plugin gp-bulk-loader-plugin kettle-drools5-plugin kettle-dummy-plugin kettle-gpload-plugin kettle-hl7-plugin kettle-openerp-plugin kettle-palo-plugin kettle-s3csvinput-plugin kettle-sap-plugin kettle-shapefilereader-plugin kettle-version-checker lucid-db-streaming-loader-plugin ms-access-bulk-loader-plugin pdi-google-analytics-plugin-ce pdi-pur-plugin pdi-salesforce-plugin pentaho-big-data-plugin pentaho-cassandra-plugin platform-utils-plugin teradata-tpt-bulk-loader
rm -rf -- /opt/pentaho/data-integration/system/karaf/system/pentaho-karaf-features/pentaho-big-data-plugin-osgi/
EOF

# Install additional libraries for Pentaho
RUN <<EOF
cd /opt/pentaho/data-integration/lib
rm postgresql-*-jdbc4.jar
wget --progress=dot:giga https://repo1.maven.org/maven2/org/postgresql/postgresql/42.3.6/postgresql-42.3.6.jar
wget --progress=dot:giga https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/21.5.0.0/ojdbc8-21.5.0.0.jar
EOF

# Install PDI Files and Configuration
COPY pentaho/data-integration /opt/pentaho/data-integration

# TODO: can these be root and just the log dirs be pdi?
COPY --chown=pdi:pdi pdi/repositories.xml /home/pdi/.kettle/ 
COPY --chown=pdi:pdi pdi/bashrc /home/pdi/.bashrc
COPY --chown=pdi:pdi pdi/pentaho /home/pdi/pentaho

# Make sure the scripts are executable and do not have windows cr/lf
RUN <<EOF
chmod +x /home/pdi/pentaho/*.sh
dos2unix /home/pdi/pentaho/*.sh
chmod +x /opt/pentaho/data-integration/*.sh
dos2unix /opt/pentaho/data-integration/*.sh
EOF

# Don't switch user here. If configured, we will switch the pdi user id (UID) 
# so we have the right permissions when bind mounting (-v) host file system.
# The new entrypoint.sh will run 'gosu' to run Pentaho as the updated pdi user
# USER pdi
WORKDIR /home/pdi/pentaho

ENV BASE_IMAGE_GIT_REPO=$GITHUB_REPOSITORY
ENV BASE_IMAGE_GIT_REF_NAME=$GITHUB_REF_NAME
ENV BASE_IMAGE_GIT_RUN_ID=$GITHUB_RUN_ID
ENV BASE_IMAGE_GIT_RUN_NUMBER=$GITHUB_RUN_NUMBER
ENV BASE_IMAGE_GIT_SHA=$GITHUB_SHA

# Write Build Info to the File System
RUN <<EOF
echo "Repository (GITHUB_REPOSITORY):   ${GITHUB_REPOSITORY}" >> /opt/pentaho/pdi-framework-pdi-pdi.build-info.txt
echo "Source Commit (GITHUB_SHA):       ${GITHUB_SHA}" >> /opt/pentaho/pdi-framework-pdi-pdi.build-info.txt
echo "Source Branch (GITHUB_REF_NAME):  ${GITHUB_REF_NAME}" >> /opt/pentaho/pdi-framework-pdi-pdi.build-info.txt
echo "Build ID (GITHUB_RUN_ID):         ${GITHUB_RUN_ID}" >> /opt/pentaho/pdi-framework-pdi-pdi.build-info.txt
echo "Build Number (GITHUB_RUN_NUMBER): ${GITHUB_RUN_NUMBER}" >> /opt/pentaho/pdi-framework-pdi-pdi.build-info.txt
EOF


# TODO: WORKDIR?
# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#workdir
# https://github.com/hadolint/hadolint/wiki/DL3003

# TODO: Other Dockerfile best practices
#       linter = https://github.com/hadolint/hadolint

ENTRYPOINT ["sh", "/home/pdi/pentaho/run_job_gosu.sh"]
