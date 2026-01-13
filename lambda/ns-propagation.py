import os
import json
import boto3
import requests
import dns.resolver
from dns.exception import DNSException

SECRET_NAME = od.environ("SLACK_URL_SECRET_NAME")
NAMESERVERS = json.loads(os.environ["NAMESERVERS"])
DOMAIN = os.environ("DOMAIN")

secrets_client = boto3.client("secretsmanager")

def get_secret():
    response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
    secret_string = response.get("SecretString")
    if not secret_string:
        raise RuntimeError("Cannot find SecretString key.")
    return json.loads(secret_string)

def lambda_handler(event, context):
    secret_url = get_secret()
    SLACK_WEBHOOK_URL = secret_url["slack-webhook-url"]
    
    propagated = True
    for ns in NAMESERVERS:
        try:
            records = dns.resolver.resolve(DOMAIN, "NS", nameservers=[ns])
        except DNSException:
            propagated = False
            break

    if propagated:
        message = f"Nameservers have propagated for {DOMAIN}."
        requests.post(SLACK_WEBHOOK_URL, json={"text": message})
    
    return {
        "status_code": 200,
        "body": json.dumps({"propagated": propagated})
    }

