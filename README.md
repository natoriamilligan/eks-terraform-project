# Deploy Web App on AWS EKS using Terraform

## Overview

Provision infrastructure using Terraform for a simple web application. The frontend will be deployed using CloudFront and S3 and the backend will be deployed on an EKS cluster.

## 🧠 What I Learned
- The EKS module for AWS saves you time by provisioning dozens of resources required to set up EKS. All you have to do is provide the module with a few arguments specific for your application
- AWS only manages the control plane. Everything else has to be set up using Kubernetes. (pods, load balancers, RBAC)
- A Kubernetes deployment manages scaling and the number of pods
- The Horizontal Pod Autoscaler (HPA) increases the number of pods in the node depending on traffic and the node metrics
- The Cluster Autoscaler watches for pending pods and determines if a new worker node needs to be provisioned
- A pod is a running instance of your app
- A worker node is an EC2 instance
- A namespace is cluster/group of pods
