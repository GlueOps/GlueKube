import json
import os

import yaml

# The container mounts everything under /opt/gluekube, which is why this used to be hardcoded.
# GLUEKUBE_BASE_PATH lets the same script run against a checkout on a workstation -- the workflow
# the readme documents, and the one `make .env` now uses. Before this, `make .env` could only ever
# read and write /opt/gluekube, so the documented manual workflow could not bootstrap itself (#470).
BASE_PATH = os.environ.get('GLUEKUBE_BASE_PATH', '/opt/gluekube/')
if not BASE_PATH.endswith('/'):
    BASE_PATH += '/'

env_output_path = BASE_PATH + '.env'
platform_file_path = BASE_PATH + 'platform.json'
ansible_output_path = BASE_PATH + 'ansible/inventory/hosts.yaml'


def require(data, *keys):
    """Return a (possibly nested) platform.json value, or stop with a message naming it.

    The previous version interpolated .get() results straight into f-strings, so a missing field
    was written to .env as the literal string "None" -- network_service_cidr=None then became the
    kubeadm serviceSubnet, and the failure surfaced much later as a cluster with no working
    service network (#467).
    """
    node = data
    path = []
    for key in keys:
        path.append(key)
        if not isinstance(node, dict) or node.get(key) is None:
            raise SystemExit(
                "platform.json is missing required field: {}".format('.'.join(path))
            )
        node = node[key]
    return node


default_structure = {
    "all": {
        "children": {
            "masters": {
                "hosts": {

                }
            },
            "workers": {
                "hosts": {

                }
            }
        }
    }
}
# Define the path to your JSON file

platform_data = {}
with open(platform_file_path, 'r') as file:
    platform_data = json.load(file)

metadata = platform_data.get('metadata') or {}

# Everything is validated up front, before either output file is written: require() stops the
# script, and a half-written hosts.yaml or .env that looks complete is worse than none at all.
cert_key = require(platform_data, "certificate_key")
token = require(platform_data, "random_token")
loadbalancer_apiserver = require(platform_data, 'control_plane_fqdn')
domain_name = require(platform_data, 'captain_domain', 'domain_name')
calico_network_calico_cidr = require(platform_data, 'metadata', 'calico_network_calico_cidr')
network_service_cidr = require(platform_data, 'metadata', 'network_service_cidr')
autoglue_org_key = require(platform_data, 'org_key')
autoglue_org_secret = require(platform_data, 'org_secret')
autoglue_org_id = require(platform_data, 'org_id')
autoglue_cluster_id = require(platform_data, 'id')
autoglue_record_id = require(platform_data, 'control_plane_record_set', 'id')
autoglue_base_url = require(platform_data, 'base_url')
# genuinely optional: calico falls back to firstFound, which is the documented behaviour.
calico_node_address_autodetection_v4 = metadata.get('calico_node_address_autodetection_v4', None)

masters = {}
workers = {}

for node_pool in platform_data["node_pools"]:
    labels = []
    taints = []
    annotations = []
    for label in node_pool.get("labels", []):
        labels.append("{}={}".format(label["key"], label["value"]))

    for annotation in node_pool.get("annotations", []):
        annotations.append("{}={}".format(annotation["key"], annotation["value"]))
    for taint in node_pool.get("taints", []):
        taints.append(f"{taint['key']}={taint['value']}:{taint['effect']}")

    for node in node_pool["servers"]:
        per_node_labels = [f"node-public-ip={node.get('public_ip_address', '')}", f"node-private-ip={node['private_ip_address']}"]

        server = {
                "ansible_host": node['private_ip_address'],
                "ansible_user": node["ssh_user"],
                "ip": node["private_ip_address"],
                "ansible_ssh_private_key_file": f"/root/.ssh/autoglue/keys/{node['ssh_key_id']}.pem",
                "extra": {
                    "labels": list(labels)+ list(per_node_labels),
                    "taints": list(taints),
                    "annotations": list(annotations)

                }
            }
        if node["role"] == "master":
           masters[node['hostname']] = server
        elif node["role"] == "worker":
           workers[node['hostname']] = server


default_structure["all"]["children"]["masters"]["hosts"] = masters
default_structure["all"]["children"]["workers"]["hosts"] = workers


with open(ansible_output_path, 'w') as yaml_file:
    yaml.dump(default_structure, yaml_file, default_flow_style=False)


# 4. Extract and Write to .env
#
# Written only when platform.json carries them, so that a payload without them falls through to
# the Dockerfile ENV defaults -- those are pinned, tested versions, and blanking them is worse
# than keeping them. Outside the container there is no such default: an unset kubernetes_version
# used to die at prepare-nodes.yaml with "list object has no element 1", and now preflight names
# it before anything is touched (#468).
version_fields = (
    'kubernetes_version',
    'kubernetes_package_version',
    'calico_chart_version',
    'calico_tigera_operator_version',
)

with open(env_output_path, 'w') as f:
    # Write explicitly (Option A)
    f.write(f"CERTIFICATE_KEY={cert_key}\n")
    f.write(f"RANDOM_TOKEN={token}\n")
    f.write(f"loadbalancer_apiserver={loadbalancer_apiserver}\n")
    f.write(f"domain_name={domain_name}\n")
    f.write(f"network_service_cidr={network_service_cidr}\n")
    f.write(f"calico_network_calico_cidr={calico_network_calico_cidr}\n")
    if calico_node_address_autodetection_v4:
        f.write(f"calico_nodeAddressAutodetectionV4={calico_node_address_autodetection_v4}\n")

    for field in version_fields:
        value = metadata.get(field)
        if value:
            f.write(f"{field}={value}\n")

    f.write(f"AUTOGLUE_ORG_KEY={autoglue_org_key}\n")
    f.write(f"AUTOGLUE_ORG_SECRET={autoglue_org_secret}\n")
    f.write(f"AUTOGLUE_ORG_ID={autoglue_org_id}\n")
    f.write(f"AUTOGLUE_CLUSTER_ID={autoglue_cluster_id}\n")
    f.write(f"AUTOGLUE_RECORD_ID={autoglue_record_id}\n")
    f.write(f"AUTOGLUE_BASE_URL={autoglue_base_url}\n")
    print(f"✅ Successfully wrote to {env_output_path} and {ansible_output_path}")
