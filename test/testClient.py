import requests # pyright: ignore[reportMissingModuleSource]
import os
from colorama import Fore, Style, init # pyright: ignore[reportMissingModuleSource]
# Import the AuthClient instance from the client package
from client.authClient import authClient

colorama_init = init(autoreset=True)
token = None
username = os.getenv("USERNAME")
password = os.getenv("PASSWORD")
service = os.getenv("SERVICE")
verify_ssl = os.getenv("VERIFY_SSL_CERTS").lower() == "true"
environment = os.getenv("ENVIRONMENT")
port = int(os.getenv("PORT"))
print(f"Running with")
print(f"    Environment:        {environment}")
print(f"    Test server port:   {port}")
if environment in ("dev", "staging"):
    httpsAuthServerUrl = "https://localhost:8443"
elif environment == "prod":
    httpsAuthServerUrl = "https://raspberry01:8443"
testServerUrl = f"http://localhost:{port}"

def test_health_endpoint_testserver():
    print(Style.BRIGHT + Fore.BLUE + "Calling /health endpoint on Test Server ...")
    print(Style.BRIGHT + Fore.BLUE + "---> Function test_health_endpoint_testserver() called <---")
    url = testServerUrl + "/health"
    http_headers = {"Content-Type": "application/json"}
    print(Style.BRIGHT + Fore.BLUE + f"Calling {url} ...")
    try:
        response = requests.get(url, headers=http_headers, timeout=5)
        print(f"GET {url} -> Status Code: {response.status_code}")
        try:
            print("Response JSON:", response.json())
        except ValueError:
            print("Response Body:", response.text)

        if response.ok:
            print(Style.NORMAL + Fore.GREEN + "Health endpoint OK")
        else:
            print(Style.BRIGHT + Fore.LIGHTRED_EX + "Health endpoint returned error")
    except requests.RequestException as e:
        print(Style.BRIGHT + Fore.LIGHTRED_EX + f"Request error: {e}")

def test_health_endpoint_authserver():
    print(Style.BRIGHT + Fore.BLUE + "Calling /health endpoint on Auth Server ...")
    print(Style.BRIGHT + Fore.BLUE + "---> Function test_health_endpoint_authserver() called <---")
    url = httpsAuthServerUrl + "/v1/monitor/health"
    http_headers = {"Content-Type": "application/json"}
    print(Style.BRIGHT + Fore.BLUE + f"Calling {url} ...")
    try:
        response = requests.get(url, headers=http_headers, timeout=5, verify=verify_ssl)
        print(f"GET {url} -> Status Code: {response.status_code}")
        try:
            print("Response JSON:", response.json())
        except ValueError:
            print("Response Body:", response.text)

        if response.ok:
            print(Style.NORMAL + Fore.GREEN + "Health endpoint OK")
        else:
            print(Style.BRIGHT + Fore.LIGHTRED_EX + "Health endpoint returned error")
    except requests.RequestException as e:
        print(Style.BRIGHT + Fore.LIGHTRED_EX + f"Request error: {e}")

def authenticate():
    print(Style.BRIGHT + Fore.BLUE + "---> Function authenticate() called <---")
    print(Style.BRIGHT + Fore.BLUE + "Delegating authentication to authClient module ...")
    try:
        print(Style.BRIGHT + Fore.BLUE + "Calling client.authClient.authenticate() ...")
        access_token = authClient.authenticate(username, password, service)
        if access_token:
            print(Style.NORMAL + Fore.GREEN + "Authentication successful")
        else:
            print(Style.BRIGHT + Fore.LIGHTRED_EX + "Authentication failed")
    except Exception as e:
        access_token = None
        print(Style.BRIGHT + Fore.LIGHTRED_EX + f"Authentication error: {e}")
    return access_token

def test_secure_endpoint():
    print(Style.BRIGHT + Fore.BLUE + "---> Function test_secure_endpoint() called <---")
    print(Style.BRIGHT + Fore.BLUE + "Call /test secure endpoint on Test Server ...")
    # ****** START - Uncomment for debug purposes in development ONLY *******
    #print(f"Access Token: {token}\n")
    # ****** END - Uncomment for debug purposes in development ONLY ********
    global token
    if not token:
        print(Style.BRIGHT + Fore.LIGHTRED_EX + "No access token available. Authenticate first.")
        return

    url = testServerUrl + "/test"
    payload = {f"service": service}
    http_headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}"
    }
    print(Style.BRIGHT + Fore.BLUE + f"Calling {url} ...")
    try:
        response = requests.post(url, 
                                 json=payload, 
                                 headers=http_headers)
        print(f"POST {url} -> Status Code: {response.status_code}")
        try:
            print("Response JSON:", response.json())
        except ValueError:
            print("Response Body:", response.text)

        if response.ok:
            print(Style.NORMAL + Fore.GREEN + "Secure endpoint call successful")
        else:
            print(Style.BRIGHT + Fore.LIGHTRED_EX + "Secure endpoint call failed")
    except requests.RequestException as e:
        print(Style.BRIGHT + Fore.LIGHTRED_EX + f"Request error: {e}")

def main():
    global token
    print(Style.BRIGHT + Fore.GREEN +"######################################################################")
    print(Style.BRIGHT + Fore.GREEN +"##### Testing Windfire Security Authentication Service Endpoints #####")
    print(Style.BRIGHT + Fore.GREEN +"######################################################################")
    print(Style.BRIGHT + Fore.BLUE + f"Environment for Windfire Security server is: {environment}")
    print(Style.BRIGHT + Fore.BLUE + f"Windfire Security server url is: {httpsAuthServerUrl}")
    print(Style.BRIGHT + Fore.BLUE + f"Test server url is: {testServerUrl}")
    print("")
    print(Style.BRIGHT + Fore.CYAN +"#####################################################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test Health endpoint on Test Server (NOT AUTHENTICATED & NO SSL ENFORCED) #####")
    print(Style.BRIGHT + Fore.CYAN +"#####################################################################################")
    test_health_endpoint_testserver()
    print("")
    print(Style.BRIGHT + Fore.CYAN +"##################################################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test Health endpoint on Auth Server (NOT AUTHENTICATED & SSL ENFORCED) #####")
    print(Style.BRIGHT + Fore.CYAN +"##################################################################################")
    test_health_endpoint_authserver()
    print("")
    print(Style.BRIGHT + Fore.CYAN +"####################################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Authenticate to Windfire Security service (SSL ENFORCED) #####")
    print(Style.BRIGHT + Fore.CYAN +"####################################################################")
    token = authenticate()
    print("")
    print(Style.BRIGHT + Fore.CYAN +"#############################################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test call to a secured endpoint (AUTHENTICATED & NO SSL ENFORCED) #####")
    print(Style.BRIGHT + Fore.CYAN +"#############################################################################")
    test_secure_endpoint()
    print("")
    
if __name__ == "__main__":
    main()