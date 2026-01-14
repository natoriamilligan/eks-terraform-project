import os
import json
import boto3
import requests
import dns.resolver
from dns.exception import DNSException

URL_SECRET_NAME = od.environ["SLACK_URL_SECRET_NAME"]
NAMESERVERS = json.loads(os.environ["NAMESERVERS"])
DOMAIN = os.environ["DOMAIN"]
SCHEDULER_NAME = os.environ["SCHEDULER_NAME"]

secrets_client = boto3.client("secretsmanager")
scheduler_client = boto3.client("scheduler")

def get_url_secret():
    response = secrets_client.get_secret_value(SecretId=URL_SECRET_NAME)
    url_string = response.get("SecretString")
    if not url_string:
        raise RuntimeError("Cannot find SecretString key.")
    return json.loads(url_string)

def lambda_handler(event, context):
    slack_url = get_url_secret()
    SLACK_WEBHOOK_URL = slack_url["slack-webhook-url"]
    
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
        scheduler_client.update_schedule(Name=SCHEDULE_NAME, State="DISABLED")
    
    return {
        "status_code": 200,
        "body": json.dumps({"propagated": propagated})
    }
