import requests
from colorama import Fore, Style, init
import os

token = None
colorama_init = init(autoreset=True)

def authenticate():
    print(Style.BRIGHT + Fore.BLUE + "Authenticating to obtain access token ...")
    post_url = "http://localhost:8000/auth"
    post_headers = {"Content-Type": "application/json"}
    username = os.getenv("USERNAME")
    password = os.getenv("PASSWORD")
    service = os.getenv("SERVICE")
    try:
        print(Style.BRIGHT + Fore.BLUE + f"Service: {service}")
        print(Style.BRIGHT + Fore.BLUE + f"Username: {username}")
        # ****** START - Uncomment for debug purposes in development ONLY ********
        # print(Style.BRIGHT + Fore.BLUE + f"Password: {'*' * len(password)}")
        # ****** END - Uncomment for debug purposes in development ONLY ********
        response = requests.post(post_url,
                                 json={'username': username, 
                                        'password': password, 
                                        'service': service},
                                 headers=post_headers)
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
    print(Style.BRIGHT + Fore.BLUE + "Call a secure endpoint ...")
    # ****** START - Uncomment for debug purposes in development ONLY *******
    #print(f"Access Token: {token}\n")
    # ****** END - Uncomment for debug purposes in development ONLY ********

def main():
    global token
    print(Style.BRIGHT + Fore.GREEN +"######################################################################")
    print(Style.BRIGHT + Fore.GREEN +"##### Testing Windfire Security Authentication Service Endpoints #####")
    print(Style.BRIGHT + Fore.GREEN +"######################################################################")
    print("")
    print(Style.BRIGHT + Fore.CYAN +"############################################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test authentication to Windfire Security service #####")
    print(Style.BRIGHT + Fore.CYAN +"############################################################")
    token = authenticate()
    print("")
    print(Style.BRIGHT + Fore.CYAN +"###########################################")
    print(Style.BRIGHT + Fore.CYAN +"##### Test call to a secured endpoint #####")
    print(Style.BRIGHT + Fore.CYAN +"###########################################")
    test_secure_endpoint()
    print("")
    
if __name__ == "__main__":
    main()