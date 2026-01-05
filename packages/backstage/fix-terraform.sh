#!/bin/bash
set -e

kubectl patch deployment backstage -n backstage --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/initContainers/0",
    "value": {
      "name": "install-tools",
      "image": "debian:12-slim",
      "command": ["/bin/bash", "-c"],
      "args": [
        "apt-get update -qq && apt-get install -y -qq ca-certificates git wget unzip curl > /dev/null 2>&1 && wget -q https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip -O /tmp/tf.zip && unzip -q /tmp/tf.zip -d /tools && chmod +x /tools/terraform && cp /usr/bin/git /tools/ && mkdir -p /tools/usr/lib /tools/lib/x86_64-linux-gnu && cp -r /usr/lib/git-core /tools/usr/lib/ && cp -r /lib/x86_64-linux-gnu/*.so* /tools/lib/x86_64-linux-gnu/ 2>/dev/null || true && cp -r /usr/lib/x86_64-linux-gnu/*.so* /tools/lib/x86_64-linux-gnu/ 2>/dev/null || true && mkdir -p /tools/etc/ssl/certs && cp -r /etc/ssl/certs/* /tools/etc/ssl/certs/ && echo Complete"
      ],
      "volumeMounts": [{"name": "terraform-tools", "mountPath": "/tools"}]
    }
  }
]'

echo "Waiting for rollout..."
kubectl rollout status deployment/backstage -n backstage --timeout=120s
