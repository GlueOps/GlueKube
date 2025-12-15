import json
import yaml

BASE_PATH = '/opt/gluekube/'
env_output_path = BASE_PATH + '.env'
platform_file_path = BASE_PATH + 'platform.json'
ansible_output_path = BASE_PATH + 'ansible/inventory/hosts.yaml'


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

masters = {}
workers = {}

for node_pool in platform_data["node_pools"]:
    labels = []
    taints = []
    for label in node_pool.get("labels", []):
        labels.append("{}={}".format(label["key"], label["value"]))
    for taint in node_pool.get("taints", []):
        taints.append(f"{taint['key']}={taint['value']}")
    for node in node_pool["servers"]:
        labels.append("node-public-ip={}".format(node["public_ip_address"]))
        labels.append("node-private-ip={}".format(node["private_ip_address"]))

        server = {
                "ansible_host": node["public_ip_address"],
                "ansible_user": node["ssh_user"],
                "ip": node["private_ip_address"],
                "ansible_ssh_private_key_file": f"/root/.ssh/autoglue/keys/{node['ssh_key_id']}.pem",
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


with open(ansible_output_path, 'w') as yaml_file:
    yaml.dump(default_structure, yaml_file, default_flow_style=False) 


# 4. Extract and Write to .env
with open(env_output_path, 'w') as f:
    # We use .get() to avoid crashing if a key is missing
    cert_key = platform_data.get("certificate_key")
    token = platform_data.get("random_token")
    loadbalancer_apiserver = platform_data.get('control_plane_fqdn')
    
    # Write explicitly (Option A)
    f.write(f"CERTIFICATE_KEY={cert_key}\n")
    f.write(f"RANDOM_TOKEN={token}\n")
    f.write(f"loadbalancer_apiserver={loadbalancer_apiserver}\n")
    
    f.write(f"AUTOGLUE_ORG_KEY={platform_data.get('org_key')}\n")
    f.write(f"AUTOGLUE_ORG_SECRET={platform_data.get('org_secret')}\n")
    f.write(f"AUTOGLUE_CLUSTER_ID={platform_data.get('id')}\n")
    
    print(f"✅ Successfully wrote to {env_output_path} and {ansible_output_path}")
