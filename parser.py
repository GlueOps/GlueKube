import json
import yaml
import subprocess

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
file_path = '/opt/gluekube/platform.json'

data = {}
with open(file_path, 'r') as file:
    data = json.load(file)

masters = {}
workers = {}

for node_pool in data["node_pools"]:
    labels = []
    taints = []
    for label in node_pool.get("labels", []):
        labels.append("{}={}".format(label["key"], label["value"]))
    for taint in node_pool.get("taints", []):
        taints.append(f"{taint['key']}={taint['value']}")
    for node in node_pool["servers"]:
        server = {
                "ansible_host": node["public_ip"],
                "ansible_user": "cluster",
                "ip": node["private_ip"],
                "ansible_ssh_private_key_file": "/opt/gluekube/keys/vm_node",
                "extra": {
                    "labels": list(labels),
                    "taints": list(taints)
                }
            }
        if node["role"] == "master":
           masters[node['hostname']] = server
        elif node["role"] == "worker":
           workers[node['hostname']] = server
           
default_structure["all"]["children"]["masters"]["hosts"] = masters
default_structure["all"]["children"]["workers"]["hosts"] = workers

file_path = '/opt/gluekube/ansible/inventory/hosts.yaml'

with open(file_path, 'w') as yaml_file:
    yaml.dump(default_structure, yaml_file, default_flow_style=False) 