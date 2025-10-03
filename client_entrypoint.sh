#!/bin/bash



RCS_BIN=/opt/Thinkbox/Deadline10/bin/deadlinercs
WEB_BIN=/opt/Thinkbox/Deadline10/bin/deadlinewebservice
WORKER_BIN=/opt/Thinkbox/Deadline10/bin/deadlineworker
FORWARDER_BIN=/opt/Thinkbox/Deadline10/bin/deadlinelicenseforwarder
DEADLINE_CMD=/opt/Thinkbox/Deadline10/bin/deadlinecommand

configure_from_env () {
    if [[ -z "$DEADLINE_REGION" ]]; then
        $DEADLINE_CMD SetIniFileSetting Region $DEADLINE_REGION
    fi
}


install_repository () {
    if [ ! -f /repo/settings/repository.ini ]; then
        echo "Install Repository"
        ./DeadlineRepository-${DEADLINE_VERSION}-linux-x64-installer.run --mode unattended \
        --dbhost $DB_HOST \
        --dbport 27100 \
        --installmongodb false \
        --installSecretsManagement true \
        --secretsAdminName $SECRETS_USERNAME \
        --secretsAdminPassword $SECRETS_PASSWORD \
        --prefix /repo \
        --dbname deadline10db \
        --dbclientcert /client_certs/deadline-client.pfx \
        --dbcertpass $DB_CERT_PASS \
        --dbssl true

        echo "Install Custom Elements from https://github.com/postwork-io/custom.git"
        git clone https://github.com/postwork-io/custom.git
        rsync --ignore-existing -raz ./custom /repo

    else
        echo "Repository Already Installed"

    fi
}

download_additional_installers () {
    
    mkdir -p /installers

    if [ ! -e "/installers/Deadline-$DEADLINE_VERSION-linux-installers.tar" ]; then
        echo "Downloading Linux Installers"
        mv Deadline-$DEADLINE_VERSION-linux-installers.tar /installers/Deadline-$DEADLINE_VERSION-linux-installers.tar
    fi

    if [ ! -e "/installers/Deadline-$DEADLINE_VERSION-windows-installers.zip" ]; then
        echo "Downloading Windows Installers"
        echo "/installers/Deadline-$DEADLINE_VERSION-windows-installers.zip" 
        aws s3 cp --region us-west-2 --no-sign-request s3://thinkbox-installers/$DEADLINE_INSTALLER_BASE-windows-installers.zip /installers/Deadline-$DEADLINE_VERSION-windows-installers.zip &
    fi

    if [ ! -e "/installers/Deadline-$DEADLINE_VERSION-osx-installers.dmg" ]; then
        echo "Downloading Mac Installers"
        aws s3 cp --region us-west-2 --no-sign-request s3://thinkbox-installers/$DEADLINE_INSTALLER_BASE-osx-installers.dmg /installers/Deadline-$DEADLINE_VERSION-osx-installers.dmg &
    fi
    wait
}

cleanup_installer () {
    rm /build/Deadline*
    rm /build/AWSPortalLink*
    rm -rf /build/custom
}

if [ "$1" == "rcs" ]; then
    
    install_repository

    echo "Deadline Remote Connection Server"
    if [ -e "$RCS_BIN" ]; then

        /bin/bash -c "$RCS_BIN"
    else # Install RCS
        download_additional_installers &
        echo "Initializing Deadline Remote Connection Server"
        if [ "$USE_RCS_TLS" != "TRUE" ]; then
            echo "Using unencrypted RCS Server!"
            /app/DeadlineClient-$DEADLINE_VERSION-linux-x64-installer.run \
            --mode unattended \
            --enable-components proxyconfig \
            --repositorydir /repo \
            --dbsslcertificate /client_certs/deadline-client.pfx \
            --dbsslpassword $DB_CERT_PASS \
            --noguimode true \
            --slavestartup false \
            --httpport $RCS_HTTP_PORT \
            --enabletls false \


        elif [ -e /client_certs/Deadline10RemoteClient.pfx ]; then
            echo "Using existing certificates"
            /app/DeadlineClient-$DEADLINE_VERSION-linux-x64-installer.run \
            --enable-components proxyconfig \
            --mode unattended \
            --repositorydir /repo \
            --dbsslcertificate /client_certs/deadline-client.pfx \
            --dbsslpassword $DB_CERT_PASS \
            --noguimode true \
            --slavestartup false \
            --httpport $RCS_HTTP_PORT \
            --tlsport $RCS_TLS_PORT \
            --enabletls true \
            --tlscertificates existing \
            --servercert /server_certs/$HOSTNAME.pfx \
            --cacert /server_certs/ca.crt \
            --secretsAdminName $SECRETS_USERNAME \
            --secretsAdminPassword $SECRETS_PASSWORD \
            --osUsername root
        else
            echo "Generating Certificates"
            /app/DeadlineClient-$DEADLINE_VERSION-linux-x64-installer.run \
            --enable-components proxyconfig \
            --mode unattended \
            --repositorydir /repo \
            --dbsslcertificate /client_certs/deadline-client.pfx \
            --dbsslpassword $DB_CERT_PASS \
            --noguimode true \
            --slavestartup false \
            --httpport $RCS_HTTP_PORT \
            --tlsport $RCS_TLS_PORT \
            --enabletls true \
            --tlscertificates generate \
            --generatedcertdir /app/certs \
            --clientcert_pass $RCS_CERT_PASS \
            --secretsAdminName $SECRETS_USERNAME \
            --secretsAdminPassword $SECRETS_PASSWORD \
            --osUsername root

            cp /app/certs/Deadline10RemoteClient.pfx /client_certs/Deadline10RemoteClient.pfx
            cp /app/certs/$HOSTNAME.pfx /server_certs/$HOSTNAME.pfx
            cp /app/certs/ca.crt /server_certs/ca.crt
        fi
        
        
        cleanup_installer
        
        "$DEADLINE_CMD" secrets ConfigureServerMachine $SECRETS_USERNAME defaultKey root --password env:SECRETS_PASSWORD

        "$RCS_BIN"
    fi

elif [ "$1" == "webservice" ] && [ "$USE_WEBSERVICE" == "TRUE" ]; then
    if [ -e "$WEB_BIN" ]; then # Already installed
        /bin/bash -c "$WEB_BIN"
    else
        echo "Initializing Deadline Webservice" # Install Webservice
        /app/DeadlineClient-$DEADLINE_VERSION-linux-x64-installer.run \
        --mode unattended \
        --enable-components webservice_config \
        --repositorydir /repo \
        --dbsslcertificate /client_certs/deadline-client.pfx \
        --dbsslpassword $DB_CERT_PASS \
        --noguimode true \
        --slavestartup false \
        --webservice_enabletls false

        cleanup_installer

        "$WEB_BIN"
    fi

elif [ "$1" == "worker" ]; then
    echo "not yet implemented"

elif [ "$1" == "forwarder" ] && [ "$USE_LICENSE_FORWARDER" == "TRUE" ]; then
    if [ -e "$FORWARDER_BIN" ]; then # Already installed
        /bin/bash -c "$FORWARDER_BIN"
    else
        echo "Initializing License Forwarder" # Install License Forwarder
        /app/DeadlineClient-$DEADLINE_VERSION-linux-x64-installer.run \
        --mode unattended \
        --repositorydir /repo \
        --dbsslcertificate /client_certs/deadline-client.pfx \
        --dbsslpassword $DB_CERT_PASS \
        --noguimode true \
        --slavestartup false \
        --secretsAdminName $SECRETS_USERNAME \
        --secretsAdminPassword $SECRETS_PASSWORD \

        cleanup_installer

        "$FORWARDER_BIN" -sslpath /client_certs
    fi

elif [ "$1" == "zt-forwarder" ]  && [ "$USE_LICENSE_FORWARDER" == "TRUE" ]; then
    if [ -e "$FORWARDER_BIN" ]; then # Already installed
        /usr/sbin/zerotier-one -d
        /bin/bash -c "$FORWARDER_BIN"
    else
        echo "Initializing ZT License Forwarder" # Install ZT License Forwarder
        /app/DeadlineClient-$DEADLINE_VERSION-linux-x64-installer.run \
        --mode unattended \
        --repositorydir /repo \
        --dbsslcertificate /client_certs/deadline-client.pfx \
        --dbsslpassword $DB_CERT_PASS \
        --noguimode true \
        --slavestartup false \
        --secretsAdminName $SECRETS_USERNAME \
        --secretsAdminPassword $SECRETS_PASSWORD \

        cleanup_installer
        
        curl -s https://install.zerotier.com | /bin/bash
        echo 9994 > /var/lib/zerotier-one/zerotier-one.port
        chmod 0600 /var/lib/zerotier-one/zerotier-one.port
        /usr/sbin/zerotier-one -d
        sleep 5
        /usr/sbin/zerotier-cli status
        /usr/sbin/zerotier-cli join $ZT_NETWORK_ID

        "$FORWARDER_BIN" -sslpath /client_certs
    fi
else
    /bin/bash 
fi
