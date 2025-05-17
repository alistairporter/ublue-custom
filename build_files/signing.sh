#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

# Signing
mkdir -p /etc/containers
mkdir -p /etc/pki/containers
mkdir -p /etc/containers/registries.d/

if [ -f /usr/etc/containers/policy.json ]; then
    cp /usr/etc/containers/policy.json /etc/containers/policy.json
fi

cat <<<"$(jq '.transports.docker |=. + {
   "ghcr.io/alistairporter/ublue-custom": [
    {
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/containers/ublue-custom.pub",
        "signedIdentity": {
            "type": "matchRepository"
        }
    }
]}' <"/etc/containers/policy.json")" >"/tmp/policy.json"
cp /tmp/policy.json /etc/containers/policy.json
cp /ctx/cosign.pub /etc/pki/containers/ublue-custom.pub
tee /etc/containers/registries.d/ublue-custom.yaml <<EOF
docker:
  ghcr.io/alistairporter/ublue-custom:
    use-sigstore-attachments: true
EOF

mkdir -p /usr/etc/containers/
cp /etc/containers/policy.json /usr/etc/containers/policy.json
