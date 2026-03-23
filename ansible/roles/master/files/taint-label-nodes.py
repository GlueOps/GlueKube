import os
import subprocess
import json

data = os.environ.get('DATA',{})
data = data.replace("'", "\"")
json_data = json.loads(data)
# Taint nodes
for taint in json_data['extra'].get('taints', []):
    subprocess.run(["kubectl", "taint", "nodes", json_data['host'], taint,"--overwrite" ])

for label in json_data['extra'].get('labels', []):
    print(["kubectl", "label", "nodes", json_data['host'], label,"--overwrite"])
    subprocess.run(["kubectl", "label", "nodes", json_data['host'], label,"--overwrite"])

for annotation in json_data['extra'].get('annotations', []):
    print(["kubectl", "annotate", "nodes", json_data['host'], annotation,"--overwrite"])
    subprocess.run(["kubectl", "annotate", "nodes", json_data['host'], annotation,"--overwrite"])