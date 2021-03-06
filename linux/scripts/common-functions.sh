#!/bin/sh

# convention: f() sets global var RESULT_f numeric variable as result, 0 means success. Transform - in _ to avoid syntax errors
# do not use "echo" mode function returns
# convention: function names in camelCase (avoid -, it is an operator)

# Source this for its reusable functions

export RED='\033[0;31m'
export NC='\033[0m' 				  	# No Color
export Green="\033[0;32m"        		# Green
export Cyan="\033[0;36m"         		# Cyan

if [[ ""${LOG_TOKEN} == "" ]]; then
    LOG_TOKEN="PUBLIC_WM_LAB Common"
fi
LOG_TOKEN_C_I="${Green}INFO - ${LOG_TOKEN}${NC}"
LOG_TOKEN_C_E="${RED}ERROR - ${Green}${LOG_TOKEN}${NC}"

logI(){
    echo -e `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN_C_I} - ${1}"
    echo `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN} -INFO- ${1}" >> ${SAG_RUN_FOLDER}/script.trace.log
}

logE(){
    echo -e `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN_C_E} - ${RED}${1}${NC}"
    echo `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN} -ERROR- ${1}" >> ${SAG_RUN_FOLDER}/script.trace.log
}

if [ -z ${SAG_DEFAULT_CERTIFICATES_PASSWORD+x} ]; then
    logI "Setting default SSL stores password!"
    export SAG_DEFAULT_CERTIFICATES_PASSWORD="changeIt"
fi

#Project Constants
export SAG_PROJECT_TRUSTSTORE="/opt/sag/certificates/projectTruststore.jks"
export SAG_MWS_KEYSTORE="/opt/sag/certificates/store/mws/full.chain.key.store.p12"


portIsReachable(){
    # Params: $1 -> host $2 -> port
    if [ -f /usr/bin/nc ]; then 
        nc -z ${1} ${2}                                         # alpine image
    else
        temp=`(echo > /dev/tcp/${1}/${2}) >/dev/null 2>&1`      # centos image
    fi
    if [ $? -eq 0 ] ; then echo 1; fi
}

takeInstallationSnapshot(){
    # $1 is the "tag" of the snapshot
    if [[ ${SAG_TAKE_SNAPHOTS} -eq 1 ]]; then
        logI "Taking snapshot ${1} ..."
        mkdir -p /${SAG_RUN_FOLDER}/snapshots/$1/
        cp -r /opt/sag/products /${SAG_RUN_FOLDER}/snapshots/$1/
    fi
}

assureRunFolder(){
    if [[ ""${SAG_RUN_FOLDER} == "" ]]; then
        export SAG_RUN_FOLDER="/opt/sag/mnt/runs/run_"`date +%y-%m-%dT%H.%M.%S`
        mkdir -p ${SAG_RUN_FOLDER}
        logI "SAG_RUN_FOLDER set to "${SAG_RUN_FOLDER}
    fi
}

assureRunFolder

bootstrapSum(){
    assureRunFolder
    logI "Bootstrapping SUM ..."
    /opt/sag/mnt/wm-install-files/sum-bootstrap.bin --accept-license -d /opt/sag/sum \
        > ${SAG_RUN_FOLDER}/sum-boot.out \
        2> ${SAG_RUN_FOLDER}/sum-boot.err
    RESULT_bootstrapSum=$?
    logI "Result: ${RESULT_bootstrapSum}"
    if [[ ${RESULT_bootstrapSum} -eq 0 ]] ; then
        logI "SUM Bootstrap successful"
    else
        logE "SUM Boostrap failed, code ${RESULT_bootstrapSum}"
    fi 
}

installProducts(){
    # param $1 is the products installation script

    logI "Installing product ..."

    /opt/sag/mnt/wm-install-files/installer.bin \
        -readScript ${1} \
        -debugLvl verbose \
        -debugFile ${SAG_RUN_FOLDER}/product-install.log \
        > ${SAG_RUN_FOLDER}/product-install.out \
        2> ${SAG_RUN_FOLDER}/product-install.err
    
    RESULT_installProducts=$?
    if [[ ${RESULT_installProducts} -eq 0 ]] ; then
        logI "Product installation successful"
    else
        logE "Product installation failed, code ${RESULT_installProducts}"
    fi 
}

patchInstallation(){
    ###### 03 - Patch installation
    # TODO: render patching optional with a parameter
    logI "Applying latest fixes ..."
    pushd .
    cd /opt/sag/sum/bin/

    if [[ ${SAG_FIXES_ONLINE} -eq 1 ]] ; then
        cat /opt/sag/mnt/scripts/unattended/wm/fixes/online-against-install-folder.wmscript.txt > /dev/shm/fixes.wmscript.txt
        cat /opt/sag/mnt/secret/empower-credentials-fixes.txt >> /dev/shm/fixes.wmscript.txt

        ./UpdateManagerCMD.sh -readScript /dev/shm/fixes.wmscript.txt \
        > ${SAG_RUN_FOLDER}/patching.out \
        2> ${SAG_RUN_FOLDER}/patching.err 
        RESULT_patchInstallation=$?
        rm /dev/shm/fixes.wmscript.txt
    else
        ./UpdateManagerCMD.sh -readScript /opt/sag/mnt/scripts/unattended/wm/fixes/offline-against-install-folder.wmscript.txt \
        > ${SAG_RUN_FOLDER}/patching.out \
        2> ${SAG_RUN_FOLDER}/patching.err
        RESULT_patchInstallation=$?
    fi
    popd
}

cleanMwsInstanceParameters(){
    unset MWS_DB_TYPE
    unset MWS_DB_HOST
    unset MWS_DB_PORT
    unset MWS_DB_NAME
    unset MWS_DB_URL
    unset MWS_DB_USERNAME
    unset MWS_DB_PASSWORD
    unset MWS_NODE_NAME
}

assureMwsInstanceParameters(){

    if [[ ""${MWS_DB_TYPE} == "" ]]; then
        export MWS_DB_TYPE="mysqlce"
    fi
    echo -e "${Green}MWS_DB_TYPE=${NC}"${MWS_DB_TYPE}

    if [[ ""${MWS_DB_HOST} == "" ]]; then
        export MWS_DB_HOST="mysql"
    fi
    echo -e "${Green}MWS_DB_HOST=${NC}"${MWS_DB_HOST}

    if [[ ""${MWS_DB_PORT} == "" ]]; then
        export MWS_DB_PORT="3306"
    fi
    echo -e "${Green}MWS_DB_PORT=${NC}"${MWS_DB_PORT}

    if [[ ""${MWS_DB_NAME} == "" ]]; then
        export MWS_DB_NAME="webmethods"
    fi
    echo -e "${Green}MWS_DB_NAME=${NC}"${MWS_DB_NAME}

    if [[ ""${MWS_DB_URL} == "" ]]; then
        if [[ ""${MWS_DB_TYPE} == "mysqlce" ]]; then
            export MWS_DB_URL="jdbc:mysql://${MWS_DB_HOST}:${MWS_DB_PORT}/${MWS_DB_NAME}?useSSL=false"
        else
            export MWS_DB_URL="NOT IMPLEMENTED YET"
        fi
    fi
    echo -e "${Green}MWS_DB_URL=${NC}"${MWS_DB_URL}

    if [[ ""${MWS_DB_USERNAME} == "" ]]; then
        export MWS_DB_USERNAME="webmethods"
    fi
    echo -e "${Green}MWS_DB_USERNAME=${NC}"${MWS_DB_USERNAME}

    if [[ ""${MWS_DB_PASSWORD} == "" ]]; then
        export MWS_DB_PASSWORD="webmethods"
    fi
    #echo -e "${Green}MWS_DB_PASSWORD=${NC}"${MWS_DB_PASSWORD}

    if [[ ""${MWS_NODE_NAME} == "" ]]; then
        export MWS_NODE_NAME="localhost"
    fi
    echo -e "${Green}MWS_NODE_NAME=${NC}"${MWS_NODE_NAME}
}

createMwsInstance(){

    assureMwsInstanceParameters
    temp=`(echo > /dev/tcp/${MWS_DB_HOST}/${MWS_DB_PORT}) >/dev/null 2>&1`
    CHK_DB_UP=$?
    
    logI "CHK_DB_UP: ${CHK_DB_UP}"

    if [[ ${CHK_DB_UP} -eq 0 ]] ; then

        takeInstallationSnapshot IC-01-before-instance-creation

        # TODO: parametrize eventually
        logI "Instance does not exist, creating ..."
        JAVA_OPTS='-Ddb.type='${MWS_DB_TYPE}

        JAVA_OPTS=${JAVA_OPTS}' -Ddb.url="'${MWS_DB_URL}'"'
        JAVA_OPTS=${JAVA_OPTS}' -Ddb.username="'${MWS_DB_USERNAME}'"'
        JAVA_OPTS=${JAVA_OPTS}' -Ddb.password="'${MWS_DB_PASSWORD}'"'

        JAVA_OPTS=${JAVA_OPTS}' -Dnode.name='${MWS_NODE_NAME}
        JAVA_OPTS=${JAVA_OPTS}' -Dserver.features=default'
        JAVA_OPTS=${JAVA_OPTS}' -Dinstall.service=false'

        #TODO: analyze further
        #JAVA_OPTS=${JAVA_OPTS}' -DjndiProviderUrl="'${}'"'
        #JAVA_OPTS=${JAVA_OPTS}' -Ddb.driver="'${}'"'

        cmd="./mws.sh new ${JAVA_OPTS}"
        
        logI "Command to execute is"
        logI "Command (1): ./mws.sh new ${JAVA_OPTS}"
        logI "Command (2): ${cmd}"

        logI "Creating default instance "
        pushd .
        cd /opt/sag/products/MWS/bin
        eval ${cmd} >/${SAG_RUN_FOLDER}/01-mws-new.out 2>/${SAG_RUN_FOLDER}/01-mws-new.err
        NEW_RET_VAL=$?
        popd

        takeInstallationSnapshot IC-02-after-creation

        if [[ ${NEW_RET_VAL} -eq 0 ]] ; then
            logI "Instance default created, initializing ..."

            if [[ ""${MWS_DB_TYPE} == "mysqlce" ]]; then
                cp /opt/sag/mnt/extra/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/common/lib/ext/
                ln -s /opt/sag/products/common/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/MWS/lib/mysql-connector-java-5.1.49.jar
                cp -r /opt/sag/mnt/extra/overwrite/install-time/mws/mysqlce/* /opt/sag/products/
            fi

            pushd .
            cd /opt/sag/products/MWS/bin
            ./mws.sh update >/${SAG_RUN_FOLDER}/02-mws-update.out 2>/${SAG_RUN_FOLDER}/02-mws-update.err
            MWS_UPD_RESULT=$?

            if [[ ${MWS_UPD_RESULT} -eq 0 ]]; then
                ./mws.sh init >/${SAG_RUN_FOLDER}/02-mws-init.out 2>/${SAG_RUN_FOLDER}/02-mws-init.err
                MWS_INIT_RESULT=$?

                takeInstallationSnapshot IC-03-after-init

                if [[ ${MWS_INIT_RESULT} -eq 0 ]] ; then
                    logI "Instance default initialized "
                    RESULT_createMwsInstance=0
                else
                    logE "Instance default not initialized, error code ${MWS_INIT_RESULT}"
                    RESULT_createMwsInstance=4 # Init failed
                fi
            else
                logE "Instance default not updated!, error code ${MWS_UPD_RESULT}"
                RESULT_createMwsInstance=3 # Update failed
            fi
            popd
        else
            logE "Instance default not created, error code ${NEW_RET_VAL}"
            RESULT_createMwsInstance=2 # Creation failed
        fi
    else
        logE "Instance cannot be created, mysql must be reachable"
        RESULT_createMwsInstance=1 # DB not ready
    fi
}

shutdownMwsContainerEntrypoint(){
    assureRunFolder

    logI "Stopping MWS"
    /opt/sag/products/profiles/MWS_default/bin/shutdown.sh >/${SAG_RUN_FOLDER}/04-stop-mws.out 2>/${SAG_RUN_FOLDER}/04-stop-mws.err

    sleep 10 # TODO: Enhance to wait for the actual shutdown (?)

    logI "Taking Install snapshot after shutdown"
    takeInstallationSnapshot after-mws-shutdown

    LogI "Stopping container"
    kill $(ps -ef | grep "/dev/null" | grep -v grep | awk '{print $2}')

}

addPemCertToProjectJksTruststore(){
    # Params: 
    # 1: pem file containing a certificate
    # 2: key alias
    # by convention, the jks trust store is ${SAG_PROJECT_TRUSTSTORE}
    # e.g. CA cart is /opt/sag/certificates/store/ca/certificateAuthority.cert.pem
    if [ -f ${1} ]; then
        /opt/sag/products/jvm/jvm/jre/bin/keytool \
            -importcert -file ${1} -alias ${2} \
            -noprompt -keystore ${SAG_PROJECT_TRUSTSTORE} \
            -storepass ${SAG_DEFAULT_CERTIFICATES_PASSWORD}
        RESULT_addPemCertToProjectJksTruststore=$?
        logI "DEBUG: Adding certificate ${1} with alias ${2} to project keystore is ${RESULT_addPemCertToProjectJksTruststore}"
    else
        logE "Certificate file ${1} not found"
    fi
}

addDefaultCACertificatesToProjectStore(){
    addPemCertToProjectJksTruststore /opt/sag/certificates/store/ca/certificateAuthority.cert.pem laboratoryCA
}

setupSslForMws(){
    if [ -z ${SAG_DEFAULT_CERTIFICATES_PASSWORD+x} ]; then
        logE "Cannot setup SSL without a passphrase. Set the variable SAG_DEFAULT_CERTIFICATES_PASSWORD first!"
        RESULT_setupSslForMws=1
    else
        addDefaultCACertificatesToProjectStore
        # TODO: enforce error management
        cafCipherUtilEncryptPassword ${SAG_DEFAULT_CERTIFICATES_PASSWORD}

        # Stores password
        sed -i "s/\(set\.JAVA_TRUSTSTORE_PASSWORD=\).*\$/\1${MY_ENCRYPTED_PASSWORD}/" /opt/sag/products/profiles/MWS_default/configuration/custom_wrapper.conf
        sed -i "s/\(set\.JAVA_KEYSTORE_PASSWORD=\).*\$/\1${MY_ENCRYPTED_PASSWORD}/" /opt/sag/products/profiles/MWS_default/configuration/custom_wrapper.conf

        # Truststore
        sed -i "s;\(set\.JAVA_TRUSTSTORE=\).*\$;\1${SAG_PROJECT_TRUSTSTORE};" /opt/sag/products/profiles/MWS_default/configuration/custom_wrapper.conf

        # Keystore
        sed -i "s;\(set\.JAVA_KEYSTORE=\).*\$;\1${SAG_MWS_KEYSTORE};" /opt/sag/products/profiles/MWS_default/configuration/custom_wrapper.conf
    fi
}

setupMwsForBpm(){
    # 2020-08-19: there are some unidentified problems when creating the instance after installation
    # switched to create the instance at install time
    assureRunFolder

    logI "Setting up MWS for BPM"

    # Note: setting up with default instance requires Database to be up and reachable
    assureMwsInstanceParameters
    temp=`(echo > /dev/tcp/${MWS_DB_HOST}/${MWS_DB_PORT}) >/dev/null 2>&1`
    CHK_DB_UP=$?
    
    logI "CHK_DB_UP: ${CHK_DB_UP}"

    if [[ ${CHK_DB_UP} -eq 0 ]] ; then
        installProducts ${SAG_SCRIPTS_HOME}/unattended/wm/products/mws/bpm-set-2.wmscript.txt
        if [[ ${RESULT_installProducts} -eq 0 ]] ; then
            takeInstallationSnapshot S-01-after-install
            logI "Bootstrapping Update Manager"
            bootstrapSum
            if [[ ${RESULT_bootstrapSum} -eq 0 ]] ; then
                logI "Applying fixes"
                patchInstallation
                takeInstallationSnapshot S-02-after-patch
                if [[ ${RESULT_patchInstallation} -eq 0 ]] ; then

                    LOCAL_INSTANCE_UPDATED=1 # i.e. assume already up to date with the exceptions below
                    if [[ "${MWS_DB_TYPE}" == "mysqlce" ]]; then
                        LOCAL_INSTANCE_UPDATED=0
                        cp /opt/sag/mnt/extra/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/common/lib/ext/
                        ln -s /opt/sag/products/common/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/MWS/lib/mysql-connector-java-5.1.49.jar
                        cp -r /opt/sag/mnt/extra/overwrite/install-time/mws/mysqlce/* /opt/sag/products/
                        pushd .
                        logI "Updating instance to conenect to MySQL Community Edition"
                        cd /opt/sag/products/MWS/bin
                        ./mws.sh getconfig cluster.xml >/${SAG_RUN_FOLDER}/03-get-cluster-config.out 2>/${SAG_RUN_FOLDER}/03-get-cluster-config.err
                        ./mws.sh update >/${SAG_RUN_FOLDER}/03-mws-update.out 2>/${SAG_RUN_FOLDER}/03-mws-update.err
                        RESULT_mws_update=$?
                        takeInstallationSnapshot S-03-after-update
                        if [[ ${RESULT_mws_update} -eq 0 ]]; then
                            logI "MWS instance updated successfully"
                            LOCAL_INSTANCE_UPDATED=1
                        else
                            LOCAL_INSTANCE_UPDATED=0
                            logE "MWS instance update failed, code: ${RESULT_mws_update}"
                        fi
                        popd
                    fi

                    if [[ ${LOCAL_INSTANCE_UPDATED} -eq 1 ]]; then
                        pushd .
                        logI "Initializing MWS instance"
                        cd /opt/sag/products/MWS/bin
                        ./mws.sh getconfig cluster.xml >/${SAG_RUN_FOLDER}/04-get-cluster-config.out 2>/${SAG_RUN_FOLDER}/04-get-cluster-config.err
                        ./mws.sh init >/${SAG_RUN_FOLDER}/04-mws-init.out 2>/${SAG_RUN_FOLDER}/04-mws-init.err
                        RESULT_mws_init=$?
                        takeInstallationSnapshot S-04-after-init
                        if [[ ${RESULT_mws_init} -eq 0 ]]; then
                            logI "MWS instance initialized successfully"
                            RESULT_setupMwsForBpm=0
                        else
                            RESULT_setupMwsForBpm=6
                            logE "MWS instance init failed, code: ${RESULT_mws_init}"
                        fi
                        popd
                    else
                        logE "Instance update failed"
                        RESULT_setupMwsForBpm=5
                    fi
                else
                    logE "Patching failed: ${PATCH_RESULT}"
                    RESULT_setupMwsForBpm=3 # 3 - patching failed
                fi
            else
                logE "SUM Bootstrap failed: ${SUM_BOOT_RESULT}"
                RESULT_setupMwsForBpm=2 # 2 - bootstrap failed
            fi
        else
            logE "Installation failed: ${INSTALL_RESULT}"
            RESULT_setupMwsForBpm=1 # 1 - installation failed
        fi
    else
        logE "Installation failed: Database not available"
        RESULT_setupMwsForBpm=1 # 4 - installation failed
    fi


}

setupMwsForBpm_old(){
    # 2020-08-19: there are some unidentified problems when creating the instance after installation
    # switched to create the instance at install time
    assureRunFolder
    logI "Setting up MWS for BPM"
    installProducts ${SAG_SCRIPTS_HOME}/unattended/wm/products/mws/bpm-set-1.wmscript.txt
    if [[ ${RESULT_installProducts} -eq 0 ]] ; then
        takeInstallationSnapshot S-01-after-install
        logI "Bootstrapping Update Manager"
        bootstrapSum
        if [[ ${RESULT_bootstrapSum} -eq 0 ]] ; then
            logI "Applying fixes"
            patchInstallation
            if [[ ${RESULT_patchInstallation} -eq 0 ]] ; then
                takeInstallationSnapshot S-02-after-patch

                logI "Creating default instance"
                createMwsInstance

                if [[ ${RESULT_createMwsInstance} -eq 0 ]] ; then
                    RESULT_setupMwsForBpm=0
                else
                    logE "Create instance failed: ${PATCH_RESULT}"
                    RESULT_setupMwsForBpm=4
                fi
            else
                logE "Patching failed: ${PATCH_RESULT}"
                RESULT_setupMwsForBpm=3 # 3 - patching failed
            fi
        else
            logE "SUM Bootstrap failed: ${SUM_BOOT_RESULT}"
            RESULT_setupMwsForBpm=2 # 2 - bootstrap failed
        fi
    else
        logE "Installation failed: ${INSTALL_RESULT}"
        RESULT_setupMwsForBpm=1 # 1 - installation failed
    fi
}

setupBpmsNodeType1(){
    assureRunFolder
    logI "Setting up Node Type 1 for BPM"
    installProducts ${SAG_SCRIPTS_HOME}/unattended/wm/products/bpmsNode/installBpmDevFullNode.wmscript.txt
    if [[ ${RESULT_installProducts} -eq 0 ]] ; then
        takeInstallationSnapshot S-01-after-install
        logI "Bootstrapping Update Manager"
        bootstrapSum
        if [[ ${RESULT_bootstrapSum} -eq 0 ]] ; then
            logI "Applying fixes"
            patchInstallation
            if [[ ${RESULT_patchInstallation} -eq 0 ]] ; then
                takeInstallationSnapshot S-02-after-patch

                # Already created (TBV)
                # logI "Creating default instance"
                # createMwsInstance

                # if [[ ${RESULT_createMwsInstance} -eq 0 ]] ; then
                #     RESULT_setupMwsForBpm=0
                # else
                #     logE "Create instance failed: ${PATCH_RESULT}"
                #     RESULT_setupMwsForBpm=4
                # fi
                RESULT_setupBpmsNodeType1=0
            else
                logE "Patching failed: ${PATCH_RESULT}"
                RESULT_setupBpmsNodeType1=3 # 3 - patching failed
            fi
        else
            logE "SUM Bootstrap failed: ${SUM_BOOT_RESULT}"
            RESULT_setupBpmsNodeType1=2 # 2 - bootstrap failed
        fi
    else
        logE "Installation failed: ${INSTALL_RESULT}"
        RESULT_setupBpmsNodeType1=1 # 1 - installation failed
    fi
}

startupMwsContainerEntrypoint(){

    unset SAG_RUN_FOLDER # force new run folder, useful only for running manually
    assureRunFolder 

    assureMwsInstanceParameters
    temp=`(echo > /dev/tcp/${MWS_DB_HOST}/${MWS_DB_PORT}) >/dev/null 2>&1`
    CHK_DB_UP=$?
    
    logI "CHK_DB_UP: ${CHK_DB_UP}"

    if [[ ${CHK_DB_UP} -eq 0 ]] ; then

        HEALTHY=1
        if [ ! -d "/opt/sag/products/MWS/server/default/bin" ] ; then
            HEALTHY=0
            logI "Container has not been set up, installing and creating the instance"
            setupMwsForBpm
            if [[ ${RESULT_setupMwsForBpm} -eq 0 ]] ; then
                logI "Setup Successful"
                HEALTHY=1
            else
                logE "Setup failed"
            fi
        fi
        if [[ ${HEALTHY} -eq 1 ]] ; then
            takeInstallationSnapshot Start-01-before-start

            # logI "Starting MWS"
            # /opt/sag/products/profiles/MWS_default/bin/startup.sh >/${SAG_RUN_FOLDER}/UP-06-mws.out 2>/${SAG_RUN_FOLDER}/UP-06-mws.err

            logI "Starting MWS, log at ${SAG_RUN_FOLDER}/run.out"
            cd /opt/sag/products/MWS/bin/
            ./mws.sh getconfig cluster.xml >/${SAG_RUN_FOLDER}/get-cluster-config-before-run.out 2>/${SAG_RUN_FOLDER}/get-cluster-config-before-run.err
            ./mws.sh run 1>>${SAG_RUN_FOLDER}/run.out 2>>run.err
            logI "MWS run exited: $? Taking snapshot"
            takeInstallationSnapshot Start-02-after-stop
        else
            logE "Cannot start, instance is not healthy"
        fi
    else
        logE "Cannot start: database must be up!"
    fi

    # TODO: Remove when ready
    logI "Stopping for debug, CTRL-C to finish"
    tail -f /dev/null
}

shutdownBpmsType1ContainerEntrypoint(){
    assureRunFolder
    logI "Stopping IS"
    /opt/sag/products/profiles/IS_default/bin/shutdown.sh >/${SAG_RUN_FOLDER}/01-stop-is.out 2>/${SAG_RUN_FOLDER}/01-stop-is.err

    logI "Stopping Analysis Engine"
    /opt/sag/products/optimize/analysis/bin/shutdown.sh >/${SAG_RUN_FOLDER}/02-stop-ae.out 2>/${SAG_RUN_FOLDER}/02-stop-ae.err

    logI "Stopping Data Collector"
    /opt/sag/products/optimize/dataCollector/bin/shutdown.sh >/${SAG_RUN_FOLDER}/03-stop-dc.out 2>/${SAG_RUN_FOLDER}/03-stop-dc.err

    logI "Stopping MWS"
    /opt/sag/products/profiles/MWS_default/bin/shutdown.sh >/${SAG_RUN_FOLDER}/04-stop-mws.out 2>/${SAG_RUN_FOLDER}/04-stop-mws.err

    logI "Stopping UM"
    /opt/sag/products/UniversalMessaging/server/umserver/bin/nserverdaemon stop >/${SAG_RUN_FOLDER}/05-stop-um.out 2>/${SAG_RUN_FOLDER}/05-stop-um.err

    logI "Stopping SPM"
    /opt/sag/products/profiles/SPM/bin/shutdown.sh >/${SAG_RUN_FOLDER}/06-stop-spm.out 2>/${SAG_RUN_FOLDER}/06-stop-spm.err

    sleep 3

    logI "Taking Install snapshot after shutdown"
    takeInstallationSnapshot after-shutdown

    LogI "Stopping container"
    kill $(ps -ef | grep "/dev/null" | grep -v grep | awk '{print $2}')
}

startupBpmsType1ContainerEntrypoint(){
    unset SAG_RUN_FOLDER # force new run folder, useful only for running manually
    assureRunFolder

    assureMwsInstanceParameters
    temp=`(echo > /dev/tcp/${MWS_DB_HOST}/${MWS_DB_PORT}) >/dev/null 2>&1`
    CHK_DB_UP=$?
    
    logI "CHK_DB_UP: ${CHK_DB_UP}"

    if [[ ${CHK_DB_UP} -eq 0 ]] ; then

        HEALTHY=1
        if [ ! -d "/opt/sag/products/MWS/server/default/bin" ] ; then
            HEALTHY=0
            logI "Container has not been set up, installing and creating the instance"
            setupBpmsNodeType1
            if [[ ${RESULT_setupBpmsNodeType1} -eq 0 ]] ; then
                logI "Setup Successful"
                # TODO: parametrize and enrich eventually
                if [[ ""${MWS_DB_TYPE} == "mysqlce" ]]; then
                    cp /opt/sag/mnt/extra/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/common/lib/ext/
                    ln -s /opt/sag/products/common/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/MWS/lib/mysql-connector-java-5.1.49.jar
                    ln -s /opt/sag/products/common/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/IntegrationServer/lib/jars/custom/mysql-connector-java-5.1.49.jar
                    cp -r /opt/sag/mnt/extra/overwrite/install-time/mws/mysqlce/* /opt/sag/products/
                    pushd .
                    cd /opt/sag/products/MWS/bin
                    ./mws.sh update >/${SAG_RUN_FOLDER}/PS01-update-mws.out 2>/${SAG_RUN_FOLDER}/PS01-update-mws.err

                    # first MWS startup needs to be controlled
                    ./mws.sh start >/${SAG_RUN_FOLDER}/PS02-start-mws.out 2>/${SAG_RUN_FOLDER}/PS02-start-mws.err

                    MWS_NOT_READY=1

                    while [ ${MWS_NOT_READY} -ne 0 ]
                    do
                        logI "Waiting for MWS to initialize"
                        sleep 60
                        ./mws.sh ping Administrator manage >/dev/null 2>/dev/null
                        MWS_NOT_READY=$?
                    done
                    logI "My WebMethods Server is ready"

                    # copy over the configuration prepared for optimize and other configuration to be passed at install time for this node
                    cp -rf /opt/sag/mnt/extra/overwrite/install-time/bpms-node-type1/* /opt/sag/products/

                    popd
                fi
                HEALTHY=1
            else
                logE "Setup failed"
            fi
        fi
        if [[ ${HEALTHY} -eq 1 ]] ; then
            takeInstallationSnapshot Start-01-before-start

            logI "Starting SPM"
            /opt/sag/products/profiles/SPM/bin/startup.sh >/${SAG_RUN_FOLDER}/UP-01-spm.out 2>/${SAG_RUN_FOLDER}/UP-01-spm.err

            logI "Starting UM"
            /opt/sag/products/UniversalMessaging/server/umserver/bin/nserverdaemon start >/${SAG_RUN_FOLDER}/UP-02-um.out 2>/${SAG_RUN_FOLDER}/UP-02-um.err

            logI "Starting IS"
            /opt/sag/products/profiles/IS_default/bin/startup.sh >/${SAG_RUN_FOLDER}/UP-03-is.out 2>/${SAG_RUN_FOLDER}/UP-01-is.err

            logI "Starting Analysis Engine"
            /opt/sag/products/optimize/analysis/bin/startup.sh >/${SAG_RUN_FOLDER}/UP-04-ae.out 2>/${SAG_RUN_FOLDER}/UP-04-ae.err

            logI "Starting Data Collector"
            /opt/sag/products/optimize/dataCollector/bin/startup.sh >/${SAG_RUN_FOLDER}/UP-05-dc.out 2>/${SAG_RUN_FOLDER}/UP-05-dc.err

            logI "Starting MWS"
            /opt/sag/products/profiles/MWS_default/bin/startup.sh >/${SAG_RUN_FOLDER}/UP-06-mws.out 2>/${SAG_RUN_FOLDER}/UP-06-mws.err
        else
            logE "Cannot start, instance is not healthy"
        fi
    else
        logE "Cannot start: database must be up!"
    fi
}
startInstallerInAttendedMode(){
    unset SAG_RUN_FOLDER # force new run folder, useful only for running manually
    assureRunFolder
    /opt/sag/mnt/wm-install-files/installer.bin -console \
        -installDir /opt/sag/products \
        -readImage /opt/sag/mnt/wm-install-files/products.zip \
        -writeScript ${SAG_RUN_FOLDER}/install.wmscript.txt
}

setupDbc(){
    assureRunFolder
    logI "Setting up Database Configurator"
    installProducts ${SAG_SCRIPTS_HOME}/unattended/wm/products/dbc/install.dbc.wmscript.txt
    if [[ ${RESULT_installProducts} -eq 0 ]] ; then
        takeInstallationSnapshot Setup-01-after-install
        logI "Bootstrapping Update Manager"
        bootstrapSum
        if [[ ${RESULT_bootstrapSum} -eq 0 ]] ; then
            logI "Applying fixes"
            patchInstallation
            if [[ ${RESULT_patchInstallation} -eq 0 ]] ; then
                takeInstallationSnapshot Setup-02-after-patch
                RESULT_setupDbc=0
            else
                logE "Patching failed: ${PATCH_RESULT}"
                RESULT_setupDbc=3 # 3 - patching failed
            fi
        else
            logE "SUM Bootstrap failed: ${SUM_BOOT_RESULT}"
            RESULT_setupDbc=2 # 2 - bootstrap failed
        fi
    else
        logE "Installation failed: ${INSTALL_RESULT}"
        RESULT_setupDbc=1 # 1 - installation failed
    fi
}

buildDbcContainer(){
    assureRunFolder
    docker info >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        if [ ! -d "/opt/sag/products/common" ] ; then
            setupDbc
            if [[ ${RESULT_setupDbc} -eq 0 ]] ; then
                logI "Building container mydbcc-1005"
                logI "Taking a snapshot of current images"
                docker images > ${SAG_RUN_FOLDER}/docker-images-before-build.out
                cp ${SAG_SCRIPTS_HOME}/unattended/wm/products/dbc/Dockerfile /opt/sag/products
                pushd .
                cd /opt/sag/products
                docker build -t mydbcc-1005 . >${SAG_RUN_FOLDER}/container-image-build.out 2>/${SAG_RUN_FOLDER}/container-image-build.err
                logI "Image built, taking a snapshot of current images"
                docker images > ${SAG_RUN_FOLDER}/docker-images-after-build.out
                docker image prune -f # remove intermediary alpine + jvm image or older untagged mydbcc
                popd
            else
                logE "Setup failed"
            fi
        else
            logE "Cannot install product: destination folder is not empty"
        fi
    else
        logE "Docker is not aailable!"
    fi
}

assureDbcParameters(){

    if [[ ""${DBC_DB_TYPE} == "" ]]; then
        export DBC_DB_TYPE="mysqlce"
    fi
    echo -e "${Green}DBC_DB_TYPE=${NC}"${DBC_DB_TYPE}

    if [[ ""${DBC_DB_HOST} == "" ]]; then
        export DBC_DB_HOST="mysql"
    fi
    echo -e "${Green}DBC_DB_HOST=${NC}"${DBC_DB_HOST}

    if [[ ""${DBC_DB_PORT} == "" ]]; then
        export DBC_DB_PORT="3306"
    fi
    echo -e "${Green}DBC_DB_PORT=${NC}"${DBC_DB_PORT}

    if [[ ""${DBC_DB_NAME} == "" ]]; then
        export DBC_DB_NAME="webmethods"
    fi
    echo -e "${Green}DBC_DB_NAME=${NC}"${DBC_DB_NAME}

    if [[ ""${DBC_DB_URL} == "" ]]; then
        if [[ ""${DBC_DB_TYPE} == "mysqlce" ]]; then
            export DBC_DB_URL="jdbc:mysql://${DBC_DB_HOST}:${DBC_DB_PORT}/${DBC_DB_NAME}?useSSL=false"
            export DBC_DB_TYPE2="mysql"
        else
            export DBC_DB_URL="NOT IMPLEMENTED YET"
            export DBC_DB_TYPE2="NOT IMPLEMENTED YET"
        fi
    fi
    echo -e "${Green}DBC_DB_URL=${NC}"${DBC_DB_URL}

    if [[ ""${DBC_DB_USERNAME} == "" ]]; then
        export DBC_DB_USERNAME="webmethods"
    fi
    echo -e "${Green}DBC_DB_USERNAME=${NC}"${DBC_DB_USERNAME}

    if [[ ""${DBC_DB_PASSWORD} == "" ]]; then
        export DBC_DB_PASSWORD="webmethods"
    fi
    #echo -e "${Green}DBC_DB_PASSWORD=${NC}"${DBC_DB_PASSWORD}
}

initializeDatabase(){

    assureRunFolder
    assureDbcParameters

    if [ `portIsReachable ${DBC_DB_HOST} ${DBC_DB_PORT}` ]; then
        B_IMPLEMENTED=0
        #copy the necessary files

        # TODO: parametrize eventually
        if [[ ""${DBC_DB_TYPE} == "mysqlce" ]]; then
            cp /opt/sag/mnt/extra/lib/ext/mysql-connector-java-5.1.49.jar /opt/sag/products/common/lib/ext/
            B_IMPLEMENTED=1
        else
            logE "DB Type ${DBC_DB_TYPE} not implemented yet.."
        fi        

        if [[ ${B_IMPLEMENTED} -eq 1 ]]; then
            cd ${SAG_INSTALL_HOME}/common/db/bin/
            ./dbConfigurator.sh \
                --action create \
                --dbms ${DBC_DB_TYPE2} \
                --url "${DBC_DB_URL}" \
                --component All \
                --user "${DBC_DB_USERNAME}" \
                --password "${DBC_DB_PASSWORD}" \
                --version latest \
                --printActions \
                > ${SAG_RUN_FOLDER}/db-initialize.out \
                2> ${SAG_RUN_FOLDER}/db-initialize.err
            # TODO: Error check
            DBC_RESULT=$?
            if [ ${DBC_RESULT} -ne 0 ] ; then
                logE "Database initialization failed: ${DBC_RESULT}"
            fi
        fi
    else
        logE "Database is not reachable! Host ${DBC_DB_HOST}; port ${DBC_DB_PORT}"
    fi
}

cleanupInstallFolder(){
    # Potential improvement for data storage

    # TODO: optimize, for the moment I found this to be more appropriate than selecting content in Dockerfile

    pushd .

    cd /opt/sag/products/profiles/SPM/bin

    ./shutdown.sh

    rm -rf /opt/sag/products/_documentation
    rm -rf /opt/sag/products/bin
    rm -rf /opt/sag/products/common/src
    rm -rf /opt/sag/products/profiles/SPM         # not useful in docker
    rm -rf /opt/sag/products/jvm/*.bck            # no backup needed
    rm -rf /opt/sag/products/jvm/jvm/src.zip
    rm -rf /opt/sag/products/jvm/jvm/demo
    rm -rf /opt/sag/products/jvm/jvm/man
    rm -rf /opt/sag/products/jvm/jvm/sample

    find /opt/sag/products -type f -iname "*.pdf" -delete

    # Special, to analyze further
    rm -rf /opt/sag/products/MWS/server/template-derby.zip

    popd
}

cafCipherUtilEncryptPassword(){

    CP="/opt/sag/products/common/lib/wm-caf-common.jar"
    CP="${CP}:/opt/sag/products/common/lib/wm-caf-common.jar"
    CP="${CP}:/opt/sag/products/common/lib/ext/slf4j-api.jar"
    CP="${CP}:/opt/sag/products/common/lib/wm-scg-security.jar"
    CP="${CP}:/opt/sag/products/common/lib/wm-scg-core.jar"
    CP="${CP}:/opt/sag/products/common/lib/ext/enttoolkit.jar"

    CMD="/opt/sag/products/jvm/jvm/jre/bin/java -cp "'"'"${CP}"'"'" com.webmethods.caf.common.CipherUtil ${1}"
    
    MY_ENCRYPTED_PASSWORD=`${CMD}`
    RESULT_cafCipherUtilEncryptPassword=$?

    if [ ${RESULT_cafCipherUtilEncryptPassword} -eq 0 ] ; then
        logI "Password encrypted successfully"
        export MY_ENCRYPTED_PASSWORD
    fi
}