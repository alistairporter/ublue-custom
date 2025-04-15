#!/usr/bin/bash

#
# https://github.com/m2Giles/m2os/blob/main/build_files/signing.sh
#

set ${SET_X:+-x} -eou pipefail

# Signing
mkdir -p /etc/containers
mkdir -p /etc/pki/containers
mkdir -p /etc/containers/registries.d/

if [ -f /usr/etc/containers/policy.json ]; then
    cp /usr/etc/containers/policy.json /etc/containers/policy.json
fi

cat <<<"$(jq '.transports.docker |=. + {
   "ghcr.io/alistairporter": [
    {
        "type": "sigstoreSigned",
        "keyPaths": [
            "/etc/pki/containers/alistairporter.pub",
            "/etc/pki/containers/alistairporter-backup.pub"
        ],
        "signedIdentity": {
            "type": "matchRepository"
        }
    }
]}' <"/etc/containers/policy.json")" >"/tmp/policy.json"

cp /tmp/policy.json /etc/containers/policy.json
cp /ctx/cosign.pub /etc/pki/containers/alistairporter.pub
cp /ctx/cosign-backup.pub /etc/pki/containers/alistairporter-backup.pub

tee /etc/containers/registries.d/alistairporter.yaml <<EOF
docker:
  ghcr.io/alistairporter:
    use-sigstore-attachments: true
EOF

mkdir -p /usr/etc/containers/
cp /etc/containers/policy.json /usr/etc/containers/policy.json
