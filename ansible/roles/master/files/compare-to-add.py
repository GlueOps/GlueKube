import json

with open("/opt/kubernetes/new_nodes_list","r") as f:
    new_nodes_list = f.read().splitlines()
with open("/opt/kubernetes/current_nodes_list","r") as f:
    current_nodes_list = f.read().splitlines()
new_diff = list(set(new_nodes_list) - set(current_nodes_list))

print(json.dumps(new_diff))