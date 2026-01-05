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
        "set -e && apt-get update -qq && apt-get install -y -qq ca-certificates git wget unzip > /dev/null 2>&1 && wget -q https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip -O /tmp/tf.zip && unzip -q /tmp/tf.zip -d /tools && chmod +x /tools/terraform && cp -r /usr/bin/git* /tools/ 2>/dev/null || true && chmod +x /tools/git && mkdir -p /tools/usr/lib /tools/lib/x86_64-linux-gnu /tools/usr/lib/x86_64-linux-gnu && cp -r /usr/lib/git-core /tools/usr/lib/ && echo Copying git dependencies... && for binary in /usr/bin/git /usr/lib/git-core/git-remote-https /usr/lib/git-core/git-remote-http; do if [ -f $binary ]; then ldd $binary 2>/dev/null | grep '=>' | awk '{print $3}' | while read lib; do if [ -f \"$lib\" ]; then cp -L \"$lib\" /tools/lib/x86_64-linux-gnu/ 2>/dev/null || true; fi; done; fi; done && cp /lib/x86_64-linux-gnu/libc.so.6 /tools/lib/x86_64-linux-gnu/ 2>/dev/null || true && cp /lib64/ld-linux-x86-64.so.2 /tools/lib/x86_64-linux-gnu/ 2>/dev/null || true && mkdir -p /tools/etc/ssl/certs && cp -r /etc/ssl/certs/* /tools/etc/ssl/certs/ && echo Installation complete && ls -lah /tools/lib/x86_64-linux-gnu/ | head -20"
      ],
      "volumeMounts": [{"name": "terraform-tools", "mountPath": "/tools"}]
    }
  }
]'

echo "✅ Patch applied, waiting for rollout..."
kubectl rollout status deployment/backstage -n backstage --timeout=120s
