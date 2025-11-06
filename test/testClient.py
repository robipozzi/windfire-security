import requests
import os
from colorama import Fore, Style, init

colorama_init = init(autoreset=True)
token = None
username = os.getenv("USERNAME")
password = os.getenv("PASSWORD")
service = os.getenv("SERVICE")
verify_ssl = os.getenv("VERIFY_SSL_CERTS").lower() == "true"
httpAuthServerUrl = os.getenv("HTTP_AUTH_SERVER_URL", "https://localhost:8443")
httpsAuthServerUrl = os.getenv("HTTPS_AUTH_SERVER_URL", "https://localhost:8443")
testServerUrl = os.getenv("TEST_SERVER_URL", "http://localhost:8001")

def test_health_endpoint_testserver():
    print(Style.BRIGHT + Fore.BLUE + "Calling /health endpoint on Test Server ...")
    url = testServerUrl + "/health"
    http_headers = {"Content-Type": "application/json"}
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
    url = httpAuthServerUrl + "/health"
    http_headers = {"Content-Type": "application/json"}
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
    print(Style.BRIGHT + Fore.BLUE + "Calling /auth endpoint on Authentication Server ...")
    print(Style.BRIGHT + Fore.BLUE + "Authenticating to obtain access token ...")
    url = httpsAuthServerUrl + "/auth"
    http_headers = {"Content-Type": "application/json"}
    try:
        print(Style.BRIGHT + Fore.BLUE + f"Service: {service}")
        print(Style.BRIGHT + Fore.BLUE + f"Username: {username}")
        # ****** START - Uncomment for debug purposes in development ONLY ********
        # print(Style.BRIGHT + Fore.BLUE + f"Password: {'*' * len(password)}")
        # ****** END - Uncomment for debug purposes in development ONLY ********
        response = requests.post(url,
                                 json={'username': username, 
                                        'password': password, 
                                        'service': service},
                                 headers=http_headers,
                                 verify=verify_ssl)
        access_token = response.json()['access_token']
        print(f"Return Code: {response.status_code}\n")
        # ****** START - Uncomment for debug purposes in development ONLY ********
        #print(f"Response Body: {response.__dict__}\n")
        #print(f"Access Token: {access_token}\n")
        # ****** END - Uncomment for debug purposes in development ONLY ********
        if not access_token is None:
            print(Style.NORMAL + Fore.GREEN + "Authentication successful")
    except Exception:
        access_token = None
        print(Style.BRIGHT + Fore.LIGHTRED_EX + "Authentication failed")
        print(f"Response: {response.__dict__} \n")
        print("POST Status Code:", response.status_code) 
    return access_token
            
def test_secure_endpoint():
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
    print("")
    print(Style.BRIGHT + Fore.CYAN +"############################################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test Health endpoint on Test Server (NO SSL & NOT AUTHENTICATED) #####")
    print(Style.BRIGHT + Fore.CYAN +"############################################################################")
    test_health_endpoint_testserver()
    print("")
    print(Style.BRIGHT + Fore.CYAN +"############################################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test Health endpoint on Auth Server (NO SSL & NOT AUTHENTICATED) #####")
    print(Style.BRIGHT + Fore.CYAN +"############################################################################")
    test_health_endpoint_authserver()
    print("")
    print(Style.BRIGHT + Fore.CYAN +"#####################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Authenticate to Windfire Security service #####")
    print(Style.BRIGHT + Fore.CYAN +"#####################################################")
    token = authenticate()
    print("")
    print(Style.BRIGHT + Fore.CYAN +"###########################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test call to a secured endpoint #####")
    print(Style.BRIGHT + Fore.CYAN +"###########################################")
    test_secure_endpoint()
    print("")
    
if __name__ == "__main__":
    main()