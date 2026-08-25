# Windfire Security
- [Introduction](#introduction)
- [Security protocols](#security-protocols)
    - [OAuth2](#OAuth2)
- [Identity and access management](#identity-and-access-management)
    - [Keycloak](#Keycloak)
        - [Run Keycloak as server on localhost](#run-keycloak-as-server-on-localhost)
        - [Install and run Keycloak as server on a Raspberry Pi box](#install-and-run-keycloak-as-server-on-a-raspberry-pi-box)
        - [Secure and run Keycloak server with TLS self signed certificate](#secure-and-run-keycloak-server-with-tls-self-signed-certificate)
        - [Run Keycloak on Docker](#run-keycloak-on-docker)
        - [Test Keycloak functioning](#test-keycloak-functioning)
- [Windfire Root CA and certificates](#windfire-root-ca-and-certificates)
- [Authentication Service](#authentication-service)
    - [First-time setup](#first-time-setup)
    - [Running the Authentication Service](#running-the-authentication-service)
    - [API endpoints](#api-endpoints)
- [Testing the Authentication Service](#testing-the-authentication-service)
- [Deployment](#deployment)

## Introduction
This repository provides the authentication/authorization infrastructure for the Windfire application suite. It has three main parts:

1. **[server/](server/)** — a Python FastAPI "Windfire Security Authentication Service" that fronts Keycloak. Other Windfire services never talk to Keycloak directly; they call this service's `/v1/security/auth` and `/v1/security/verify` endpoints instead.
2. **[keycloak/](keycloak/)** — shell scripts to run Keycloak itself (localhost, Docker, or Raspberry Pi) and to configure TLS on the Keycloak server.
3. **[ssl/](ssl/)** — shell scripts to generate the Windfire self-signed Root CA and per-host server certificates used across the whole Windfire suite (not just this service).

A companion sibling repo, `windfire-security-client`, provides the client module other services (and this repo's own `test/` scripts) use to call the Authentication Service.

## Security protocols
Security protocols are foundational elements of modern IT systems, serving as standardized frameworks for securing communication and data exchange over networks. 

These protocols define rules and procedures that govern authentication, encryption, and data integrity, ensuring confidentiality, integrity, and availability of information. 

By implementing security protocols such as TLS, SSH, and IPsec, organizations can establish secure connections, authenticate users and devices, and protect against unauthorized access and data breaches. 

Security protocols play a critical role in fortifying IT infrastructures, safeguarding sensitive data, and upholding the trust and integrity of digital interactions.

### OAuth2
OAuth2 is a security protocol playing a pivotal role in securing APIs and applications by providing a standardized way of handling authentication.

OAuth2 defines four roles (as described in https://datatracker.ietf.org/doc/html/rfc6749#section-1.1):
* **Resource Owner**: An entity capable of granting access to a protected resource. When the resource owner is a person, it is referred to as an end-user.
* **Resource server**: The server hosting the protected resources, capable of accepting and responding to protected resource requests using access tokens.
* **Client**: An application making protected resource requests on behalf of the resource owner and with its authorization. The term "client" does not imply any particular implementation characteristics (e.g., whether the application executes on a server, a desktop, or other devices).
* **Authorization server**: The server issuing access tokens to the client after successfully authenticating the resource owner and obtaining authorization.

Conceptually, an OAuth2 enabled architecture looks like the following picture.

![](img/OAuth2_enabled_architecture.png)

## Identity and access management
Identity and Access Management (IAM) systems are fundamental components of modern cybersecurity strategies, providing organizations with the means to manage and control access to their digital resources. 

IAM systems enable businesses to securely authenticate users, grant appropriate permissions, and enforce policies across diverse IT environments. 

By centralizing user identities and access controls, IAM solutions streamline user provisioning, simplify compliance efforts, and mitigate security risks associated with unauthorized access. These systems play a crucial role in safeguarding sensitive data, protecting against insider threats, and ensuring regulatory compliance within organizations.

### Keycloak
Keycloak is an Open Source Identity and Access Management technology that allows to add authentication mechanisms to applications, securing them with minimum effort.

Keycloak provides user federation, strong authentication, user management, fine-grained authorization, and more.

![](img/Keycloak_NoTLS.png)

As we all modern technologies, Keycloak can be deployed in different ways:

- A comprehensive guide on how to download, install and run Keycloak with OpenJDK is available here https://www.keycloak.org/getting-started/getting-started-zip
- A comprehensive guide on how to run Keycloak in Docker is available on Keycloak official website https://www.keycloak.org/getting-started/getting-started-docker.

A convenient script **[start-keycloak.sh](keycloak/start-keycloak.sh)** is provided to run Keycloak in one of the following mode

![](img/Select_how_to_run_keycloak.png)

#### Run Keycloak as server on localhost
In case *option 1* is selected, the script just runs the **<KEYCLOAK_HOME>/bin/kc.sh** command provided by Keycloak; **KEYCLOAK_HOME** needs to be set in **[common.sh](common.sh)** to point to actual Keycloak installation directory on your platform.

Keycloak Admin console will respond on http://localhost:8080/admin. The first time you launch it, you will need to create an admin user that will secure all the following accesses, follow the instructions at *https://www.keycloak.org/getting-started/getting-started-zip* to create admin credentials.

#### Install and run Keycloak as server on a Raspberry Pi box
[TODO]

#### Secure and run Keycloak server with TLS self signed certificate
Keycloak can be configured to run with TLS enabled, loading the required certificate infrastructure using files in PEM format or from a Java Keystore. When both alternatives are configured, the PEM files takes precedence over the Java Keystores.

I referred to official Keycloak documentation instructions *https://www.keycloak.org/server/enabletls* to enable TLS on Keycloak server.

A convenient script **[setupTLS.sh](keycloak/security/setupTLS.sh)** is provided to generate a server keystore in *tls* subfolder.

The script currently uses keytool to generate a Java keystore; for the sake of simplicity I use a self signed certificate. 

Once keytool command is launched, it asks for some info, my choices are something similar to the following

![](img/keytool_create_keystore.png)

Once the server keystore has been generated, run **[setupKeycloakMode.sh](keycloak/setupKeycloakMode.sh)**, which provides two options to enable and disable TLS respectively

![](img/Select_enable_disable_TLS.png)

If *option 1* is selected, the script does the following:

1. it copies server keystore to **<KEYCLOAK_HOME>/conf** folder
2. it runs **<KEYCLOAK_HOME>/bin/kc.sh build** command to rebuild Keycloak configuration and fully enable TLS

Once everything has been properly setup, to run Keycloak with TLS enabled, we just need to select *option 2* when **[start-keycloak.sh](keycloak/start-keycloak.sh)** script is launched.

Keycloak Admin console will respond on https://localhost:8443/admin. Since the certificate is self signed, browsers will complain but we can accept the risk and continue (**WARNING: a proper certificate signed by a Certification Authority must be used for production**).

#### Run Keycloak on Docker
In case Docker is selected, Keycloak will run with the following default parameters values:
* **Keycloak Docker Image** set to *quay.io/keycloak/keycloak*
* **Keycloak Docker Image version** set to *23.0.3*
* **Keycloak Container name** set to *keycloak*
* **Keycloak Port** remapped and exposed on *8081*
* **Keycloak Admin console username** rset to *admin*

The script will only require to input the Password for Keycloak Admin console.

With these default values, once the container is running, Keycloak Admin Console will be available at **http://localhost:8081/admin**.

#### Test Keycloak functioning
A convenient script **[testKeycloak.sh](keycloak/test/testKeycloak.sh)** is provided to run a simple curl command to authenticate with Keycloak and get back the authentication token to verify everything is setup and works fine.

The script allows to select whether TLS on Keycloak server is enabled or not

![](img/Select_test.png)

## Windfire Root CA and certificates
The [ssl/](ssl/) folder contains the scripts used to generate the Windfire self-signed Root CA and the per-host server certificates used across the whole Windfire suite, independently of Keycloak's own TLS setup described above.

- **[createRootCA.sh](ssl/createRootCA.sh)** generates the Windfire self-signed Root CA (`WindfireRootCA.key`/`.crt`) and copies it into `~/opt/windfire/ssl/{keystore,truststore}`.
- **[generateServerCert.sh](ssl/generateServerCert.sh)** issues per-host server certificates off that CA, using **[openssl_config_localhost.ext](ssl/openssl_config_localhost.ext)** or **[openssl_config_raspberry.ext](ssl/openssl_config_raspberry.ext)** as the SAN configuration depending on the target host.

These are the certificates that `SSL_KEYFILE`/`SSL_CERTFILE` in the Authentication Service configuration point at (see below), and that the test scripts verify against.

## Authentication Service
The [server/](server/) folder contains the Windfire Security Authentication Service: a FastAPI application that fronts Keycloak so that other Windfire services never need to talk to Keycloak directly.

### First-time setup
Copy the two placeholder configuration files (both gitignored — never commit real values):

```bash
cd server
cp .env_PLACEHOLDER .env
cp config/service_config.json_PLACEHOLDER config/service_config.json
```

- **`.env`** sets `APP_NAME`, `API_HOST`, `API_PORT`/`API_PORT_SECURE`, `SSL_KEYFILE`/`SSL_CERTFILE`, `ENFORCE_HTTPS`, `ALLOWED_HOSTS` and `KEYCLOAK_SERVER_URL`.
- **`config/service_config.json`** is a per-service Keycloak `realm`/`client_id`/`client_secret` map, keyed by service name (e.g. `windfire-calendar-srv`). This is how a single Authentication Service instance backs multiple Windfire client services.

### Running the Authentication Service
```bash
cd server
./start-auth-server.sh              # creates/activates venv, installs deps, runs on port 8000 (HTTP) or 8443 (HTTPS)
./start-auth-server.sh -p 9000      # custom port
./start-auth-server.sh -v           # verbose/DEBUG logging
./run-auth-server-background.sh     # same, but backgrounded, logs to logs/windfire-security-server.log
./stop-auth-server.sh               # stops the background server
```

**[createPythonVenv.sh](server/createPythonVenv.sh)** / **[activatePythonVenv.sh](server/activatePythonVenv.sh)** / **[deactivatePythonVenv.sh](server/deactivatePythonVenv.sh)** manage a dedicated Python virtual environment; **[installPrereqs.sh](server/installPrereqs.sh)** pins the FastAPI/uvicorn/PyJWT/cryptography/python-dotenv versions installed into it.

### API endpoints
Routes are nested under a version prefix:
- `GET /v1/monitor/health` — service health check.
- `POST /v1/security/auth` — authenticates a user against Keycloak (via `authenticate_user`) and returns tokens.
- `POST /v1/security/verify` — verifies a token, by default locally against Keycloak's public keys (no special Keycloak client permissions needed).

## Testing the Authentication Service
There's no automated test suite — the [test/](test/) folder contains manual/interactive scripts that exercise a running Authentication Service end-to-end:

```bash
cd test
./start-test-server.sh -e dev       # runs a dummy service with one endpoint protected by the Authentication Service
./run-test-client.sh -e dev         # hits health endpoints, authenticates via Keycloak, calls the protected endpoint
```

Both scripts prompt interactively for username/password/service, defaulting the service to `windfire-calendar-srv`. The `-e {dev|staging|prod}` flag selects which Authentication Service instance to target. **[installPrereqs.sh](test/installPrereqs.sh)** additionally installs the sibling `windfire-security-client` repo in editable mode.

## Deployment
The [deployment/](deployment/) folder contains Ansible playbooks to deploy the Authentication Service (`server/`) to a Raspberry Pi:

```bash
cd deployment
./deploy.sh      # deploys the Authentication Service to the configured Raspberry Pi
./undeploy.sh    # tears it down
```

Both scripts prompt for a target platform (currently only Raspberry Pi is supported) and drive the playbooks under **[deployment/raspberry/](deployment/raspberry/)**, configured via **[conf/config.yaml](deployment/raspberry/conf/config.yaml)**.
