ARG DB_CERT_PASS
ARG SECRETS_USERNAME
ARG SECRETS_PASSWORD
ARG DB_HOST
ARG DEADLINE_VERSION
ARG DEADLINE_INSTALLER_BASE
ARG CERT_ORG
ARG CERT_OU

FROM ubuntu:18.04 as base

WORKDIR /build

RUN apt-get update && apt-get install -y curl dos2unix python python-pip git && apt-get clean && rm -rf /var/lib/apt/lists/*




FROM base as db

ARG DB_CERT_PASS
ARG SECRETS_USERNAME
ARG SECRETS_PASSWORD
ARG DB_HOST
ARG DEADLINE_VERSION
ARG DEADLINE_INSTALLER_BASE
ARG CERT_ORG
ARG CERT_OU

RUN mkdir ~/keys

# Generate Certificates using openssl. This is done in a single RUN layer for efficiency.
RUN CA_SUBJ="/O=${CERT_ORG}/OU=${CERT_OU}/CN=Deadline-CA" && \
    # 1. Generate CA Key and Certificate
    openssl genrsa -out keys/ca.key 4096 && \
    openssl req -new -x509 -days 3650 -key keys/ca.key -out keys/ca.crt -subj "${CA_SUBJ}" && \
    # 2. Generate Server Key and CSR
    openssl genrsa -out keys/${DB_HOST}.key 4096 && \
    openssl req -new -key keys/${DB_HOST}.key -out keys/${DB_HOST}.csr -subj "/CN=${DB_HOST}" && \
    # 3. Create SAN config and sign Server Certificate with CA
    printf "subjectAltName=DNS:localhost,DNS:${DB_HOST},IP:127.0.0.1" > keys/san.ext && \
    openssl x509 -req -days 3650 -in keys/${DB_HOST}.csr -CA keys/ca.crt -CAkey keys/ca.key -CAcreateserial -out keys/${DB_HOST}.crt -extfile keys/san.ext && \
    # 4. Generate Client Key and CSR
    openssl genrsa -out keys/deadline-client.key 4096 && \
    openssl req -new -key keys/deadline-client.key -out keys/deadline-client.csr -subj "/CN=deadline-client" && \
    # 5. Sign Client Certificate with CA and create PFX
    openssl x509 -req -days 3650 -in keys/deadline-client.csr -CA keys/ca.crt -CAkey keys/ca.key -CAcreateserial -out keys/deadline-client.crt && \
    openssl pkcs12 -export -out keys/deadline-client.pfx -inkey keys/deadline-client.key -in keys/deadline-client.crt -certfile keys/ca.crt -passout env:DB_CERT_PASS && \
    # 6. Create mongodb.pem for the server
    cat keys/${DB_HOST}.crt keys/${DB_HOST}.key > keys/mongodb.pem

RUN mkdir /client_certs

#Install Database
RUN mkdir -p /opt/Thinkbox/DeadlineDatabase10/mongo/data &&\
 mkdir -p /opt/Thinkbox/DeadlineDatabase10/mongo/application &&\
 mkdir -p /opt/Thinkbox/DeadlineDatabase10/mongo/data/logs

COPY ./database_config/config.conf /opt/Thinkbox/DeadlineDatabase10/mongo/data/

RUN curl https://downloads.mongodb.org/linux/mongodb-linux-x86_64-ubuntu1804-4.2.12.tgz -o mongodb.tgz && \
    tar -xvf mongodb.tgz && \
    mv mongodb-linux-x86_64-ubuntu1804-4.2.12/bin/* /opt/Thinkbox/DeadlineDatabase10/mongo/application/bin/ && \
    rm mongodb.tgz && rm -rf mongodb-linux-x86_64-ubuntu1804-4.2.12

ADD ./database_entrypoint.sh .
RUN dos2unix ./database_entrypoint.sh && chmod u+x ./database_entrypoint.sh

ENTRYPOINT [ "./database_entrypoint.sh" ]



FROM base as client

ARG DEADLINE_VERSION
ARG DEADLINE_INSTALLER_BASE


RUN pip install awscli
RUN aws s3 cp --region us-west-2 --no-sign-request s3://thinkbox-installers/${DEADLINE_INSTALLER_BASE}-linux-installers.tar Deadline-${DEADLINE_VERSION}-linux-installers.tar
RUN tar -xvf Deadline-${DEADLINE_VERSION}-linux-installers.tar

RUN mkdir ~/certs


RUN apt-get update && apt-get install -y lsb && apt-get clean && rm -rf /var/lib/apt/lists/*

ADD ./client_entrypoint.sh .
RUN dos2unix ./client_entrypoint.sh && chmod u+x ./client_entrypoint.sh


ENTRYPOINT [ "./client_entrypoint.sh" ]
