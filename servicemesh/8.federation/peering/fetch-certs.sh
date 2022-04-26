#!/bin/bash

# For peering mesh-one with mesh-two
oc get cm istio-ca-root-cert -n mesh-two -o jsonpath='{.data.root-cert\.pem}' > /tmp/mesh-two.pem
oc create configmap mesh-two-ca-root-cert -n mesh-one --from-file=root-cert.pem=/tmp/mesh-two.pem
# For peering mesh-two with mesh-one
oc get cm istio-ca-root-cert -n mesh-one -o jsonpath='{.data.root-cert\.pem}' > /tmp/mesh-one.pem
oc create configmap mesh-one-ca-root-cert -n mesh-two --from-file=root-cert.pem=/tmp/mesh-one.pem

# federate meshes
oc apply -f peering-mesh-one.yaml
oc apply -f peering-mesh-two.yaml
