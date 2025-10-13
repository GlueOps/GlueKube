# AWS EC2 Terraform Setup for GlueKube

This directory contains Terraform configuration to deploy a Kubernetes cluster on AWS EC2, converting the Hetzner-based setup to AWS infrastructure.

## Structure
- `provider.tf`: AWS provider configuration
- `variables.tf`: Input variables
- `vpc.tf`: VPC, subnets, and networking
- `ec2.tf`: EC2 instances for master and workers, security groups
- `outputs.tf`: Useful outputs

## Usage
1. Set your AWS credentials/profile.
2. Adjust variables in `variables.tf` as needed (e.g., region, subnets, key_name).
3. Run:
   ```sh
   terraform init
   terraform plan
   terraform apply
   ```

## Notes
- This is a basic conversion. You may need to further adapt user-data, EBS, IAM, and other resources for production.
- SSH key must exist in AWS (`key_name` variable).
