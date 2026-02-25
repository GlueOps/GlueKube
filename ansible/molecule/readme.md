- create .env file with the following data:
```
export kubernetes_version=v1.33.7
export kubernetes_package_version=1.33.7-1.1
export loadbalancer_apiserver="domain"
export CERTIFICATE_KEY=""
export RANDOM_TOKEN=""
export calico_chart_version=v3.29.3
export calico_tigera_operator_version=v1.36.7

export ANSIBLE_ROLES_PATH=/workspaces/glueops/GlueKube/ansible/roles


# this envs because we are using internal tool to manage route53 records 

export AUTOGLUE_BASE_URL=""

export AUTOGLUE_ORG_KEY=""
export AUTOGLUE_ORG_SECRET=""
export AUTOGLUE_ORG_ID=""

export AUTOGLUE_RECORD_ID="" 

export AUTOGLUE_CLUSTER_ID=empty

# HCLOUD TOKEN
export HCLOUD_TOKEN=""

```

- source .env

- move to Gluekube/ansible and run: molecule test -s "name_of_test", example: molecule test -s scale-cluster
