# pod-migration: local registry on the bastion

Run on the bastion. `BASTION_IP` is the address the cluster nodes use to
reach the bastion.

## 1. Start a local registry
Plain HTTP, data kept in a Docker volume, restarts with Docker.
```bash
BASTION_IP=10.62.1.241          # change to your bastion's address as seen by the nodes
docker run -d --name registry --restart=always -p 5000:5000 \
  -v registry-data:/var/lib/registry registry:2
curl -s http://localhost:5000/v2/_catalog      # → {"repositories":[]}
```

## 2. Copy the controller source to the bastion
From wherever you have the repo:
```bash
scp -r /workspaces/glueops/pod-migration cluster@$BASTION_IP:~/
```

## 3. Build and push the images
On the bastion. Docker accepts plain-HTTP pushes to `localhost` without
extra configuration, so the images are tagged and pushed as
`localhost:5000`. It's the same registry the nodes reach as
`$BASTION_IP:5000`.
```bash
cd ~/pod-migration/controller
TAG=$(sed -n 's/^appVersion: *//p' charts/pod-migration/Chart.yaml)   # v0.2.0
make push REGISTRY=localhost:5000 TAG=$TAG
```
Without `make`, the equivalent is:
```bash
for c in manager agent redirect; do
  n=pod-migration-$c
  docker build -f Dockerfile.$c -t localhost:5000/$n:$TAG . && docker push localhost:5000/$n:$TAG
done
```
For `test/e2e.sh`, also build the test writer:
```bash
docker build -t localhost:5000/db-writer:v2 ~/pod-migration/db-writer-test && docker push localhost:5000/db-writer:v2
```
Check:
```bash
curl -s http://localhost:5000/v2/_catalog
# {"repositories":["db-writer","pod-migration-agent","pod-migration-manager","pod-migration-redirect"]}
```

## 4. values.yaml
```yaml
registry:
  url: "10.62.1.241:5000"        # $BASTION_IP:5000 (what the nodes use)
  insecure: true                 # plain HTTP
  username: ""                   # no auth on this registry
  password: ""
  pullSecret: ""

# images default to <registry.url>/pod-migration-{manager,agent,redirect}:<appVersion>,
# so no images: overrides are needed.

# Pod CIDR,Service CIDR of the new cluster (change):
#   kubectl get ippools.projectcalico.org -o custom-columns=CIDR:.spec.cidr
#   kubectl cluster-info dump | grep -m1 -o 'service-cluster-ip-range=[^"]*'
internalCIDRs: "172.16.0.0/16,192.168.0.0/16"

namespace:
  create: true                   # pod-security=privileged label for the agent

# Relays for connections to databases/APIs outside the cluster: one entry
# per external endpoint. Jobs use them with the redirect annotation (below).
relays:
  - name: orders-db              # → orders-db.pod-migration.svc.cluster.local
    target: 10.62.1.241:5432     # external host:port (change)
    # port: 5432                 # listen port; defaults to the target's port

relayDefaults:
  nodeSelector:
    migrate.glueops.dev/relay: "true"   # label exactly one node (step 6)
```

A Job that talks to `10.62.1.241:5432` then opts in with:
```yaml
metadata:
  labels:
    migrate.glueops.dev/live: "true"
  annotations:
    migrate.glueops.dev/redirect: "10.62.1.241:5432=orders-db.pod-migration.svc.cluster.local:5432"
```
The app keeps connecting to the real address; the redirect rewrites it to
the relay, so the connection survives a migration.

## 5. Let the nodes pull from it over HTTP
GlueKube env, set before `make setup`. Without it the agent and manager end
up in `ImagePullBackOff`.
```bash
live_migration_enabled=true
live_migration_insecure_registries=10.62.1.241:5000
containerd_package_version=2.3.6-1~ubuntu.24.04~noble
```

## 6. Label the relay node
One node that's drained but not rebooted during maintenance (or rebooted
last). Relays never restart on `helm upgrade` (`updateStrategy: OnDelete`),
but a reboot of this node cuts the connections going through them.
```bash
kubectl label node <relay-node> migrate.glueops.dev/relay=true
```

## 7. Install
```bash
helm upgrade --install pod-migration pod-migration/controller/charts/pod-migration \
  -n pod-migration -f pod-migration/controller/charts/pod-migration/values.yaml
```

## 8. Test
```bash
REGISTRY=10.62.1.241:5000 ~/pod-migration/test/e2e.sh <node-a> <node-b>
```
`<node-a>` and `<node-b>` are two nodes labelled `migrate.glueops.dev/criu=ready`.

To also run the external-database cases, give the script SSH access to the
bastion. It starts a throwaway Postgres there in docker (port 15432), checks
that a direct connection is refused, then migrates a Job twice through the
chart's relay on the same DB session, and removes the container at the end:
```bash
REGISTRY=10.62.1.241:5000 \
E2E_BASTION_ADDRESS=10.62.1.241 \
E2E_BASTION_USER=cluster \
E2E_BASTION_SSH_KEY=~/.ssh/id_ed25519 \
  ~/pod-migration/test/e2e.sh <node-a> <node-b>
```
Optional:
- `E2E_EXTERNAL_DB_HOST`: the address pods use to reach the bastion, if it
  differs from the SSH address
- `E2E_EXTERNAL_DB_PORT`: default `15432`; must be reachable from the pods
- `E2E_RELAY_NODE`: by default the first untainted worker that isn't
  node-a/node-b, labelled for the test and unlabelled after
- `E2E_TOLERATE_TAINT_KEY`: if node-a/node-b are tainted

The registry has no auth, and the checkpoint images it will hold contain
process memory, including secrets. Keep port 5000 reachable only from the
cluster network.
