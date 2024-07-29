##### Terminal Colors - START
red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
blu=$'\e[1;34m'
mag=$'\e[1;35m'
cyn=$'\e[1;36m'
end=$'\e[0m'
coffee=$'\xE2\x98\x95'
coffee3="${coffee} ${coffee} ${coffee}"
##### Terminal Colors - END

###### Variable section - START
## Keycloak settings
KEYCLOAK_HOME=/opt/keycloak/keycloak-25.0.2
KEYCLOAK_DOCKER_IMAGE=quay.io/keycloak/keycloak
KEYCLOAK_DOCKER_IMAGE_VERSION=25.0.2
KEYCLOAK_CONTAINER_NAME=keycloak
KEYCLOAK_SERVER_ADDRESS=localhost
KEYCLOAK_SERVER_PORT=8080
KEYCLOAK_TLS_SERVER_PORT=8443
KEYCLOAK_USERNAME=admin
## Keycloak Security settings
DEFAULT_TLS_DIR=$HOME/dev/windfire-security/keycloak/security/tls
DEFAULT_KEYSTORE=server.keystore
DEFAULT_KEYSTORE_ALIAS=keycloak
DEFAULT_VALIDITY=1000
DEFAULT_CSR=keycloak.csr

# Certificate authority settings
DEFAULT_CA_KEYSTORE=ca_keycloak.jks
DEFAULT_CA_ALIAS=ca_keycloak
DEFAULT_CACERT=ca_keycloak.cer
DEFAULT_CACERT_PEM=ca_keycloak.pem

# Signed certificate settings
DEFAULT_SERVER_CERTIFICATE=keycloak.cer

# Truststore settings
DEFAULT_TRUSTSTORE_DIR=$HOME/opt/keycloak/ssl/truststore
DEFAULT_TRUSTSTORE=keycloak.truststore.jks
DEFAULT_PKCS12_TRUSTSTORE=keycloak.truststore.p12
DEFAULT_PEM_TRUSTSTORE=keycloak.truststore.pem
###### Variable section - END