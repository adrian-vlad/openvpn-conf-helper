#!/bin/bash -e

COLOR_GREEN='\033[38;5;10m'
COLOR_NONE='\033[0m'

DEFAULT_KEY_SIZE=4096
DEFAULT_DH_SIZE=${DEFAULT_KEY_SIZE}

DEFAULT_PORT=49803

EASY_RSA_DIR="easy_rsa"
KEYS_DIR_NAME="keys"

DH_FILE_NAME="dh${DEFAULT_DH_SIZE}.pem"
CA_CRT_NAME="ca.crt"
TLS_CRYPT_KEY_NAME="tc.key"

# TODO: ECDH instead of DH

function easy_rsa_install
{
    # TODO: only install if it is not
    sudo apt-get install -y easy-rsa
}

function cadir_initialize
{
    # install easy rsa
    easy_rsa_install

    make-cadir "${EASY_RSA_DIR}"
    cd "${EASY_RSA_DIR}"

    echo "export KEY_ALTNAMES=something" >> vars
    echo >> vars
    sed -i "/ KEY_COUNTRY=/c\export KEY_COUNTRY='RO'" vars
    sed -i "/ KEY_PROVINCE=/c\export KEY_PROVINCE='VN'" vars
    sed -i "/ KEY_CITY=/c\export KEY_CITY='Pufesti'" vars
    sed -i "/ KEY_ORG=/c\export KEY_ORG='Trans-Utopia Cruiseship HHS'" vars
    sed -i "/ KEY_EMAIL=/c\export KEY_EMAIL='me@myhost.mydomain'" vars
    sed -i "/ KEY_OU=/c\export KEY_OU=" vars

    source ./vars > /dev/null
    ./clean-all
    cd - > /dev/null
}

function dh_create
{
    # initialize cadir
    if [ ! -d "${EASY_RSA_DIR}" ]; then
        cadir_initialize
    fi

    if [ -f ${DH_FILE_NAME} ]; then
        cp ${DH_FILE_NAME} "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/"
        return
    fi

    cd "${EASY_RSA_DIR}"

    sed -i "/ KEY_SIZE=/c\export KEY_SIZE=${DEFAULT_DH_SIZE}" vars

    source vars > /dev/null

    # build
    ./build-dh

    cd - > /dev/null
}

function ca_create
{
    # initialize cadir
    if [ ! -d "${EASY_RSA_DIR}" ]; then
        cadir_initialize
    fi
    cd "${EASY_RSA_DIR}"

    KEY_NAME="ca"
    sed -i "/ KEY_SIZE=/c\export KEY_SIZE=${DEFAULT_KEY_SIZE}" vars
    sed -i "/ KEY_NAME=/c\export KEY_NAME=${KEY_NAME}" vars
    sed -i "/ KEY_CN=/c\export KEY_CN=${KEY_NAME}" vars

    source vars > /dev/null

    # build
    ./build-ca

    cd - > /dev/null
}

function server_crt_create
{
    # initialize cadir
    if [ ! -d "${EASY_RSA_DIR}" ]; then
        cadir_initialize
    fi
    cd "${EASY_RSA_DIR}"

    KEY_NAME="ca"
    sed -i "/ KEY_SIZE=/c\export KEY_SIZE=${DEFAULT_KEY_SIZE}" vars
    sed -i "/ KEY_NAME=/c\export KEY_NAME=${1}" vars
    sed -i "/ KEY_CN=/c\export KEY_CN=${1}" vars

    source vars > /dev/null

    # build
    ./build-key-server "${1}"

    cd - > /dev/null
}

function client_crt_create
{
    cd "${EASY_RSA_DIR}"

    KEY_NAME="ca"
    sed -i "/ KEY_SIZE=/c\export KEY_SIZE=${DEFAULT_KEY_SIZE}" vars
    sed -i "/ KEY_NAME=/c\export KEY_NAME=${1}" vars
    sed -i "/ KEY_CN=/c\export KEY_CN=${1}" vars

    source vars > /dev/null

    # build
    ./build-key "${1}"

    cd - > /dev/null
}

function config_type_read
{
    echo "Choose the usage of the config"
    echo
    echo "1. server config"
    echo "2. client config"
    echo "3. exit"
    echo

    while true; do
        echo -n "Enter your selection [1-3] "; read continue

        case $continue in
            1)  CONFIG_TYPE=server; echo -e "\nYou chose ${COLOR_GREEN}${CONFIG_TYPE}${COLOR_NONE}\n"; break;;
            2)  CONFIG_TYPE=client; echo -e "\nYou chose ${COLOR_GREEN}${CONFIG_TYPE}${COLOR_NONE}\n"; break;;
            3)  CONFIG_TYPE=exit; echo -e "\nYou chose ${COLOR_GREEN}${CONFIG_TYPE}${COLOR_NONE}\n"; break;;
            *)  echo -e "\nselection is not an option.\n";;
        esac
    done
}

function server_config_create
{
    # info
    echo -n "Enter your server name: "; read continue
    SERVER_NAME="${continue}"
    while true; do
        echo -n "Enter the port number [${DEFAULT_PORT}] "; read continue

        if [ -z "${continue}" ]; then
            break
        fi

        re='^[0-9]+$'
        if [[ "${continue}" =~ ${re} ]] && [ "${continue}" -lt "65535" ]; then
            DEFAULT_PORT=${continue}
            break
        fi

        echo -e "\nselection is not an option.\n"
    done
    echo -n "Enter dns server: "; read continue
    DNS_SERVER="${continue}"

    # dh
    if [ ! -f "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${DH_FILE_NAME}" ]; then
        echo -e "\n${COLOR_GREEN}There is no dh parameter file.\nGenerating one now...${COLOR_NONE}\n"
        dh_create
    fi

    # ca
    if [ ! -f "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${CA_CRT_NAME}" ]; then
        echo -e "\n${COLOR_GREEN}There is no ca certificate.\nGenerating one now...${COLOR_NONE}\n"
        ca_create
    fi

    # crt
    echo -e "\n${COLOR_GREEN}Generating the certificate${COLOR_NONE}\n"
    server_crt_create ${SERVER_NAME}

    # tls-crypt
    echo "#" > "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}"
    echo "# 4096 bit OpenVPN static key" >> "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}"
    echo "#" >> "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}"
    echo "-----BEGIN OpenVPN Static key V1-----" >> "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}"
    dd if=/dev/urandom count=512 bs=1 2> /dev/null | xxd -p -c 16 >> "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}"
    echo "-----END OpenVPN Static key V1-----" >> "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}"

    # add the head of the conf
    cat conf.head > server.conf
    # add the tail of the conf
    cat server.conf.tail >> server.conf
    # add the user configurable options
    echo -e "# User configurable" >> server.conf
    echo -e "port '${DEFAULT_PORT}'" >> server.conf
    echo -e "push \"dhcp-option DNS ${DNS_SERVER}\"" >> server.conf
    echo -e "tls-crypt '${TLS_CRYPT_KEY_NAME}'" >> server.conf
    echo -e "dh '${DH_FILE_NAME}'" >> server.conf
    echo -e "ca '${CA_CRT_NAME}'" >> server.conf
    echo -e "cert '${SERVER_NAME}.crt'" >> server.conf
    echo -e "key '${SERVER_NAME}.key'" >> server.conf

    mkdir -p ${SERVER_NAME}
    cp "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}" ${SERVER_NAME}/
    cp "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${DH_FILE_NAME}" ${SERVER_NAME}/
    cp "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${CA_CRT_NAME}" ${SERVER_NAME}/
    cp "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${SERVER_NAME}.crt" ${SERVER_NAME}/
    cp "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${SERVER_NAME}.key" ${SERVER_NAME}/
    mv server.conf ${SERVER_NAME}/

    echo -e "\n${COLOR_GREEN}Your server configs are in ${SERVER_NAME}/ directory${COLOR_NONE}\n"
}

function client_config_create
{
    echo -n "Enter your client name: "; read continue
    CLIENT_NAME=$continue
    while true; do
        echo -n "Enter the port number [${DEFAULT_PORT}] "; read continue

        if [ -z "${continue}" ]; then
            break
        fi

        re='^[0-9]+$'
        if [[ "${continue}" =~ ${re} ]] && [ "${continue}" -lt "65535" ]; then
            DEFAULT_PORT=${continue}
            break
        fi

        echo -e "\nselection is not an option.\n"
    done
    echo -n "Enter server host: "; read continue
    SERVER_HOST="${continue}"

    # crt
    echo -e "\n${COLOR_GREEN}Generating the certificate${COLOR_NONE}\n"
    client_crt_create ${CLIENT_NAME}

    # add the head of the conf
    cat conf.head > ${CLIENT_NAME}.ovpn
    # add the tail of the conf
    cat client.conf.tail >> ${CLIENT_NAME}.ovpn
    # add the encryption certificates
    echo -e "<ca>" >> ${CLIENT_NAME}.ovpn
    cat "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${CA_CRT_NAME}" >> ${CLIENT_NAME}.ovpn
    echo -e "</ca>" >> ${CLIENT_NAME}.ovpn
    echo -e "<cert>" >> ${CLIENT_NAME}.ovpn
    cat "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${CLIENT_NAME}.crt" >> ${CLIENT_NAME}.ovpn
    echo -e "</cert>" >> ${CLIENT_NAME}.ovpn
    echo -e "<key>" >> ${CLIENT_NAME}.ovpn
    cat "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${CLIENT_NAME}.key" >> ${CLIENT_NAME}.ovpn
    echo -e "</key>" >> ${CLIENT_NAME}.ovpn
    echo -e "<tls-crypt>" >> ${CLIENT_NAME}.ovpn
    cat "${EASY_RSA_DIR}/${KEYS_DIR_NAME}/${TLS_CRYPT_KEY_NAME}" >> ${CLIENT_NAME}.ovpn
    echo -e "</tls-crypt>" >> ${CLIENT_NAME}.ovpn
    # add the user configurable options
    echo -e "# User configurable" >> ${CLIENT_NAME}.ovpn
    echo -e "remote ${SERVER_HOST} ${DEFAULT_PORT}" >> ${CLIENT_NAME}.ovpn

    echo -e "\nYour client config file is ${COLOR_GREEN}${CLIENT_NAME}.ovpn${COLOR_NONE}\n"
}

while true; do
    config_type_read

    case ${CONFIG_TYPE} in
        server)
            server_config_create
            ;;
        client)
            client_config_create
            ;;
        exit)
            break
            ;;
    esac
done
