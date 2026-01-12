import os
import json
import requests
import dns.resolver
from dns.exception import DNSException

SLACK_WEBHOOK_URL = os.environ("SLACK_WEBHOOK_URL")
NAMESERVERS = os.environ("NAMESERVERS")
DOMAIN = os.environ("DOMAIN")

def lambda_handler(event, context):
    propagated = True
    for ns in NAMESERVERS:
        try:
            records = dns.resolver.resolve(DOMAIN, "NS", nameservers=[ns])
        except DNSException:
            propagated = False
            break

    if propagated:
        message = f"Nameservers have propagated for {DOMAIN}."
        requests.post(SLACK_WEBHOOK_URL, "text": message)
    
    return {
        "status_code": 200,
        "body": json.dump({"propagated": propagated})
    }

