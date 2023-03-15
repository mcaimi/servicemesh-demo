# Openshift Service Mesh Demo

This is a simple example of how to build a service-mesh enabled application with Quarkus and Tekton.

This demo implements a small Quarkus App that connects to a PostgreSQL database that stores simple notes. An AngularJS frontend is provided as well as a REST API endpoint.

Openshift ServiceMesh acts as an additional network service overlay that enriches the application with additional observability, security and routing features.

The code contained in this repository shows a simple real-world application that implements the following features:

- An application that is service-mesh enabled.
- Traffic is optionally encrypted by configuring mTLS on the service mesh overlay
- The application is built with Tekton Pipelines
- Request routing to different service versions by uri matching.
- Kustomize templates for deployment are provided in this repository

The application code is based on the Quarkus Application that is found [here](https://github.com/mcaimi/k8s-demo-app). That application (which is based on Quarkus 1.13.2) is deployed as "v1" inside the service mesh.
Another instance of the same application acts as "v2". The application has been rebased to the latest Quarkus release and can be found [here](https://github.com/mcaimi/quarkus-notes).

## Building the container image using Tekton on Openshift Container Platform (or Kubernetes)

This example pipeline needs Openshift Pipelines Operator in order to run. Please use the deployment manifests stored in this [repo](https://github.com/mcaimi/ocp4-argocd) to deploy the pipeline operator or add the component directly from the Openshift Console:

![Pipeline Operator Installation](/assets/tekton-operator.png)

### Running the example on Minikube

This demo is openshift-specific but it can be run on Kubernetes/Minikube as well, although that has not been tested for now.
To run the demo on Minikube a local minikube cluster with at the very least 4vCPU and 8GB of RAM is required. Also, be sure to enable the ingress and OLM addons when deploying the instance.

There should be no issues in running the Quarkus application and all Tekton pipelines (install the upstream tekton operator from [here](https://operatorhub.io/operator/tektoncd-operator)). Expect some issues with upstream [istio](https://istio.io/latest/docs/setup/platform-setup/minikube/) however because the upstream version of Istio and Openshift ServiceMesh are different in many aspects.

Refer [here](https://istio.io) and [here](https://docs.openshift.com/container-platform/4.9/service_mesh/v2x/ossm-about.html) for more information.

### Install The Openshift Service Mesh Control Plane

1. Deploy the ServiceMesh Operator

Deploy the operator using the provided Kustomize templates:

```bash
$ kustomize build --reorder none servicemesh/1.operator | oc apply -f -
```

or add the operator from the Openshift Console:

![ServiceMesh Operator](/assets/ossm-operator.png)

2. Deploy the ServiceMesh Control Plane

Deploy the control plane using the provided Kustomize templates:

```bash
$ kustomize build servicemesh/2.controlplane | oc apply -f -
```

This will install a complete control plane with ingress and egress gateways, IstioD, jaeger and kiali (to save resources, no persistence for tracing data is configured).

After a while, the control plane should be up and running:

![ossm-controlplane](/assets/ossm-controlplane.png)

### Install and run tekton pipeline manifests to build the application

1. Create a new project:

```bash
$ oc new-project istio-demo
```

2. Install tekton pipeline objects:

For the container image build pipeline:

```bash
for i in build-pvc pipeline-resources quarkus-maven-task quarkus-build-task cleanup-workspace-task quarkus-build-pipeline; do
  oc create -f tekton/$i.yaml -n istio-demo
done
```

3. Run the pipeline for app versions 1 and 2

for v1:

```bash
$ oc create -f tekton/quarkus-build-pipelinerun-v1.yaml -n istio-demo
```

for v2:

```bash
$ oc create -f tekton/quarkus-build-pipelinerun-v2.yaml -n istio-demo
```

Monitor the pipelines until completion:

```bash
@ >> tkn pipelinerun list
NAME                           STARTED         DURATION    STATUS
v1-container-build-run-wl99x   3 minutes ago   2 minutes   Succeeded
v2-container-build-run-h8tv9   7 minutes ago   3 minutes   Succeeded
```

![PipelineRun](/assets/pipelinerun.png)

Once completed, two new ImageStreamTags should be ready to be used in new deployments:

```bash
^ >> oc get imagestreams
NAME                IMAGE REPOSITORY                                                                TAGS           UPDATED
demo-app-frontend   image-registry.openshift-image-registry.svc:5000/istio-demo/demo-app-frontend   v2,v1          2 minutes ago
```

## Deploy the Demo Application

1. Enroll the namespace into the Service Mesh:

```bash
$ oc create -f servicemesh/3.application/servicemesh-membership.yaml
```

this ensures that the namespace is correctly linked to and managed by the ServiceMesh Control Plane:

```bash
^ >> oc get smm
NAME      CONTROL PLANE                 READY   AGE
default   istio-system/istio-ctlplane   True    17h
```

2. Deploy the application

Deploy the backend database and all needed objects by using the provided Kustomize templates:

```bash
$ kustomize build deployments/postgres | oc apply -f -
```

```bash
$ kustomize build deployments/quarkus-app-v1 | oc apply -f -
```

3. Create Istio Objects

Configure the ServiceMesh to manage the deployed application:

```bash
$ oc create -f servicemesh/3.application/istio-gateway.yaml # the istio ingress gateway
$ oc create -f servicemesh/3.application/postgres-virtualservice.yaml # the istio virtual service that exposes the Postgres Database
$ oc create -f servicemesh/3.application/quarkus-destinationrule.yaml # Destination rule that maps application version 1 to a specific k8s deployment
$ oc create -f servicemesh/3.application/quarkus-virtualservice.yaml # Virtual Service that exposes the Quarkus Application
```

The application (version1) is deployed and managed by Istio:

```bash
NAME                                                                  READY   STATUS      RESTARTS   AGE
pod/backend-postgres-v1-community-659f558995-tvlwg                    2/2     Running     0          17h
pod/frontend-java-runner-v1-d9cb5b647-8wwxt                           2/2     Running     0          100m

NAME                                            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
service/backend-postgres-service-v1-community   ClusterIP   172.30.244.121   <none>        5432/TCP,5433/TCP   17h
service/frontend-java-runner-service-v1         ClusterIP   172.30.75.56     <none>        80/TCP              114m

NAME                                                                        HOST                                    AGE
destinationrule.networking.istio.io/postgres-app-destination-v1-community   backend-postgres-service-v1-community   106m
destinationrule.networking.istio.io/quarkus-app-destination-v1              frontend-java-runner-service-v1         108m

NAME                                                  GATEWAYS                   HOSTS                                       AGE
virtualservice.networking.istio.io/postgres-demo-vs                              ["backend-postgres-service-v1-community"]   17h
virtualservice.networking.istio.io/quarkus-demo-vs    ["quarkus-demo-gateway"]   ["quarkus-notes.apps.lab01.gpslab.club"]    94m

NAME                                               AGE
gateway.networking.istio.io/quarkus-demo-gateway   17h
```

![frontendv1](/assets/frontend-v1.png)

In Kiali, the application topology is automatically discovered and displayed:

![kiali-app-v1](/assets/kiali-v1.png)

At this point, all requests are routed from the istio Ingress Gateway to the service exposing the quarkus app version 1, which in turn uses the backend DB.

### Deploy Authorization Policies

The deployment application can be secured by deploying Istio AuthorizationPolicies. Policies will be sent to all envoy proxies and enforced by the Mesh.

For example, we may want to restrict access to the frontend application to only allow HTTP and API calls coming from the Istio Gateway:

```yaml
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
 name: frontend-authz
 namespace: istio-demo
spec:
 selector:
   matchLabels:
     app: k8s-quarkus-app
 action: ALLOW
 rules:
 - from:
     - source:
         principals: ["cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
   to:
     - operation:
        method: ["GET", "POST"]
        paths: ["/notes/*"]
     - operation:
        method: ["GET"]
        paths: ["/", "*png", "*js"]
```
The above manifest instructs Istio to only allow traffic coming from workloads running under the ingress gateway service account: the policy allows 'GET' and 'POST' http calls to the '/notes/' API endpoint and only 'GET' calls to static content.

To secure access to the background DB anoter manifest needs to be deployed:

```yaml
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
 name: postgres-authz
 namespace: istio-demo
spec:
 selector:
   matchLabels:
     app: k8s-postgres-app
     version: v1-community
 action: ALLOW
 rules:
 - from:
   - source:
       principals:
         - "cluster.local/ns/istio-demo/sa/frontend-java-runner-sa-v1"
         - "cluster.local/ns/istio-demo/sa/frontend-java-runner-sa-v2"
   to:
     -  operation:
          ports: ["5432"]
```

The above manifest will only allow TCP traffic directed to port 5432/TCP and only from workloads running under application service accounts.

```bash
$ oc create -f servicemesh/4.authorization_policy/frontend-authz.yaml
$ oc create -f servicemesh/4.authorization_policy/postgres-authz.yaml
```

### Encrypt traffic on the Mesh Overlay

By default, all traffic flowing between Envoy Proxies is not encrypted. Encryption can be enabled by using mTLS globally on the control plane or by setting up a Policy on a per-namespace basis.

This can be done by setting up a PeerAuthentication manifest with a STRICT tls policy:

```yaml
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: mtls-enable-policy
  namespace: istio-demo
spec:
  mtls:
    mode: STRICT
```

This ensures that all traffic to/from envoy proxies is tunneled trough TLS.

```bash
$ oc create -f servicemesh/5.mTLS/mtls-policy.yaml
```

To set up mutual TLS for services, a DestinationRule needs to be declared for every service version:

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: postgres-app-destination-v1-community
spec:
  host: backend-postgres-service-v1-community
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

this service declares an ISTIO_MUTUAL TLS policy which means that certificates are automatically generated and rotated by the Service Mesh control plane.
A Destination Route is needed for both PostgreSQL and Quarkus App.

```bash
# PostgreSQL
$ oc apply -f postgres-destinatiorule.yaml
$ oc apply -f postgres-virtualservice.yaml
# Quarkus App
$ oc apply -f quarkus-destinationrule.yaml
$ oc apply -f quarkus-virtualservice.yaml

$ oc get vs,dr,peerauthentication -n istio-demo
NAME                                                  GATEWAYS                   HOSTS                                       AGE
virtualservice.networking.istio.io/postgres-demo-vs                              ["backend-postgres-service-v1-community"]   93m
virtualservice.networking.istio.io/quarkus-demo-vs    ["quarkus-demo-gateway"]   ["quarkus-notes.apps.lab01.gpslab.club"]    93m

NAME                                                                        HOST                                    AGE
destinationrule.networking.istio.io/postgres-app-destination-v1-community   backend-postgres-service-v1-community   14s
destinationrule.networking.istio.io/quarkus-app-destination-v1              frontend-java-runner-service-v1         3h27m

NAME                                                      MODE     AGE
peerauthentication.security.istio.io/mtls-enable-policy   STRICT   25s
```

Traffic is now encrypted between virtual services. On the Kiali interface, the application graph displays a keylock icon to show all encrypted data flows:

![mtls-flow](/assets/kiali-tls.png)

### Route traffic to multiple service versions

1. Deploy quarkus application version 2 using the provided kustomize templates:

```bash
$ kustomize build deployments/quarkus-app-v2 | oc create -f -
```

2. Deploy Istio Manifests

In the current namespace there are now two distinct quarkus-app deployments (v1,v2). A new virtual service will route all API calls to the app version1 endpoint, while routing all requests to the frontend page to the app version2 deployment:

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: quarkus-demo-vs
spec:
  hosts:
    - quarkus-notes.apps.lab01.gpslab.club
  gateways:
  - quarkus-demo-gateway
  http:
  - name: "Frontend served by v2"
    match:
    - uri:
        exact: /
    - uri:
        regex: '^.*\.(ico|png|jpg)$'
    route:
    - destination:
        host: frontend-java-runner-service-v2
        subset: app-v2
        port:
          number: 80
  - name: "API served by v1"
    match:
    - uri:
        prefix: /notes
    route:
    - destination:
        host: frontend-java-runner-service-v1
        subset: app-v1
        port:
          number: 80
```

```bash
# create destinationrule that maps application version 2
$ oc create -f servicemesh/6.versioning/quarkus-destinationrule-v2.yaml
# update the virtual service to route traffic to both services
$ oc apply -f servicemesh/6.versioning/quarkus-virtualservice.yaml

$ oc get pod,deployment,vs,dr,gw -n istio-demo
NAME                                                                  READY   STATUS      RESTARTS   AGE
pod/backend-postgres-v1-community-659f558995-tvlwg                    2/2     Running     0          19h
pod/frontend-java-runner-v1-d9cb5b647-8wwxt                           2/2     Running     0          3h30m
pod/frontend-java-runner-v2-7766c85574-sgrqs                          2/2     Running     0          3h36m

NAME                                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/backend-postgres-v1-community   1/1     1            1           19h
deployment.apps/frontend-java-runner-v1         1/1     1            1           3h45m
deployment.apps/frontend-java-runner-v2         1/1     1            1           3h36m

NAME                                                  GATEWAYS                   HOSTS                                       AGE
virtualservice.networking.istio.io/postgres-demo-vs                              ["backend-postgres-service-v1-community"]   105m
virtualservice.networking.istio.io/quarkus-demo-vs    ["quarkus-demo-gateway"]   ["quarkus-notes.apps.lab01.gpslab.club"]    105m

NAME                                                                        HOST                                    AGE
destinationrule.networking.istio.io/postgres-app-destination-v1-community   backend-postgres-service-v1-community   11m
destinationrule.networking.istio.io/quarkus-app-destination-v1              frontend-java-runner-service-v1         3h39m
destinationrule.networking.istio.io/quarkus-app-destination-v2              frontend-java-runner-service-v2         8s

NAME                                               AGE
gateway.networking.istio.io/quarkus-demo-gateway   19h
```
Subsequent visits to the public URL will show the new UI while routing all API calls to the original endpoint:

![new-ui](/assets/frontend-v2.png)

Kiali now recomputes the service graph accordingly:

![kiali-v2](/assets/kiali-v2.png)

### Migrate API traffic to API v2 (Jaeger-enabled)

To redirect all traffic to the V2 endpoint even for API calls (which are instrumented by Jaeger), the virtualservice must be modified:

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: quarkus-demo-vs
spec:
  hosts:
    - quarkus-notes.apps.lab01.gpslab.club
  gateways:
  - quarkus-demo-gateway
  http:
  - name: "Frontend and API served by v2"
    route:
    - destination:
        host: frontend-java-runner-service-v2
        subset: app-v2
        port:
          number: 80

```

Then, update the running manifests:

```bash
# update the virtualservice
$ oc apply -f servicemesh/7.service_move/quarkus-virtualservice.yaml
# remove old manifests that are no more needed
$ oc delete dr quarkus-app-destination-v1 quarkus-app-destinations
destinationrule.networking.istio.io "quarkus-app-destination-v1" deleted
destinationrule.networking.istio.io "quarkus-app-destinations" deleted

# remove quarkus-v1 deployment
$ kustomize build deployments/quarkus-app-v1|oc delete -f -
```

The new service graph is now updated in Kiali:

![kiali-v3](/assets/kiali-v3.png)

Since the API backend is now configured to send spans to the Jaeger collector, tracing info related to API calls are displayed in the Jaeger console:

![jaeger](/assets/jaeger.png)

## Multicluster Federation

Openshift ServiceMesh supports Federation between two or more meshes running locally on the same cluster or running across different cluster instances.
Federation allows Administrators to manage and view two or more Istio Meshes as if they were one and allows applications to consume services from any of the federated evironments.

The example consists of:

1. Two Istio Meshes running inside the same Openshift Cluster
2. Peering is configured via ClusterIP services (if deploying on different clusters, LoadBalancer or NodePort type service are required)
3. One mesh will expose the application frontend
4. The other mesh will export the database as a federated service

### Deploy Meshes

Deploy both meshes with kustomize:

```bash
# Mesh One
$ kustomize build --reorder none servicemesh/8.federation/mesh-one | oc apply -f -
# Mesh Two
$ kustomize build --reorder none servicemesh/8.federation/mesh-two | oc apply -f -
```

This operation will create :

1. Mesh One control plane + frontend-namespace as its member project
2. Mesh Two control plane + backend-namespace as its member project

Control Planes are already configured for federation (i.e. both meshes declare their own trust domain and ingress/egress pairs for federation)

### Extract root-ca certificates and configure peering

For every mesh, save the istio root CA certificate in a configmap. This CA is valid for the trust domain specified in the SCMP manifests of both meshes:

```bash
# For peering mesh-one with mesh-two
$ oc get cm istio-ca-root-cert -n mesh-two -o jsonpath='{.data.root-cert\.pem}' > /tmp/mesh-two.pem
$ oc create configmap mesh-two-ca-root-cert -n mesh-one --from-file=root-cert.pem=/tmp/mesh-two.pem
# For peering mesh-two with mesh-one
$ oc get cm istio-ca-root-cert -n mesh-one -o jsonpath='{.data.root-cert\.pem}' > /tmp/mesh-one.pem
$ oc create configmap mesh-one-ca-root-cert -n mesh-two --from-file=root-cert.pem=/tmp/mesh-one.pem
```

This will allow discovery and mutual tls authentication between Istio deployments. Peering is configured by declaring ServiceMeshPeer manifests:

```yaml
kind: ServiceMeshPeer
apiVersion: federation.maistra.io/v1
metadata:
  name: mesh-two
  namespace: mesh-one
spec:
  remote:
    addresses:
    - mesh-one-ingress.mesh-two.svc.cluster.local
    discoveryPort: 8188
    servicePort: 15443
  gateways:
    ingress:
      name: mesh-two-ingress
    egress:
      name: mesh-two-egress
  security:
    trustDomain: mesh-two.local
    clientID: mesh-two.local/ns/mesh-two/sa/mesh-one-egress-service-account
    certificateChain:
      kind: ConfigMap
      name: mesh-two-ca-root-cert
```

Apply peering manifests:

```bash
$ oc apply -f servicemesh/8.federation/peering/peering-mesh-one.yaml
$ oc apply -f servicemesh/8.federation/peering/peering-mesh-two.yaml
```

Peering is mutual, so configuration needs to be performed on both sides. After a while, peering should be up & running:

For Mesh One to Mesh Two:

```yaml
#  oc get servicemeshpeer mesh-two -o yaml -n mesh-one
status:
  discoveryStatus:
    active:
    - pod: istiod-mesh-one-6cbb95f8dc-khgs4
      remotes:
      - connected: true
        lastConnected: "2022-04-07T07:48:40Z"
        lastFullSync: "2022-04-07T07:53:40Z"
        source: 10.131.1.99
```

And for Mesh Two to Mesh One:

```yaml
#  oc get servicemeshpeer mesh-one -o yaml -n mesh-two
status:
  discoveryStatus:
    active:
    - pod: istiod-mesh-two-74dd58d75-5ps47
      remotes:
      - connected: true
        lastConnected: "2022-04-07T07:48:42Z"
        lastFullSync: "2022-04-07T07:52:54Z"
        source: 10.131.1.94
```

### Export Services Across Meshes

Federation assumes that services running in either mesh are *exported* from their source environment explicitly. Federating two or more meshes together does not automatically allow services on one mesh to consume endpoints on other meshes.

*MESH TWO*: Deploy the Database Service in Mesh Two

Deploy a PostgreSQL instance in the backend-namespace:

```bash
# deploy postgres in mesh-two
$ kustomize build --reorder none servicemesh/8.federation/workload/postgres-mesh-two | oc apply -f -
```
The service is displayed in the Kiali Console for the backend-cluster mesh instance:

![mesh-backend-cluster](/assets/mesh-backend-cluster.png)

Now from this namespace, export the postgres service in order to be consumed from the service running in mesh-one:

```yaml
kind: ExportedServiceSet
apiVersion: federation.maistra.io/v1
metadata:
  name: mesh-one
  namespace: mesh-two
spec:
  exportRules:
  # export services with the correct label set
  - type: LabelSelector
    labelSelector:
      namespace: backend-namespace
      selector:
        matchLabels:
          app: k8s-postgres-app
      aliases:
      - alias:
          namespace: backend
```

this manifest will match any service with the *app: k8s-postgres-app* label and re-export them to the mesh-one peer.

```bash
$ oc apply -f servicemesh/8.federation/federated-services/mesh-two/exported-service-set.yaml -n mesh-two
```

Once exported, the service should be listed in the status field of the ExportedServiceSet object in mesh-two namespace:

```json
$ oc get exportedserviceset.federation.maistra.io/mesh-one -n mesh-two -o jsonpath='{.status}' | jq .
{
  "exportedServices": [
    {
      "exportedName": "postgres-service.backend.svc.mesh-one-exports.local",
      "localService": {
        "hostname": "postgres-service.backend-namespace.svc.cluster.local",
        "name": "postgres-service",
        "namespace": "backend-namespace"
      }
    }
  ]
}
```

*MESH ONE*: Deploy the Quarkus frontend in Mesh One

The Frontend Service will be built and deployed in the frontend-namespace, which is a member of Mesh One:

```bash
# Build the application
$ for i in build-pvc pipeline-resources quarkus-maven-task quarkus-build-task cleanup-workspace-task quarkus-build-pipeline; do
  oc create -f tekton/$i.yaml -n frontend-namespace
done
$ oc replace -f servicemesh/8.federation/workload/tekton/pipeline-resources.yaml -n frontend-namespace
$ oc create -f servicemesh/8.federation/workload/tekton/quarkus-build-pipelinerun-v2.yaml -n frontend-namespace
```

As with the backend before, the application is visible in the Kiali console of the frontend-cluster mesh:

![mesh-frontend-cluster](/assets/mesh-frontend-cluster.png)

Finally, the exported service exposed from mesh-two needs to be imported locally in order to be consumed from mesh-one:

```bash
$ oc apply -n mesh-one -f servicemesh/8.federation/federated-services/mesh-one/imported-service-set.yaml
```

This will deploy an Imported Service Set manifest:

```yaml
kind: ImportedServiceSet
apiVersion: federation.maistra.io/v1
metadata:
  name: mesh-two
  namespace: mesh-one
spec:
  importRules: # first matching rule is used
  - type: NameSelector
    importAsLocal: false
    nameSelector:
      namespace: backend
      name: postgres-service
      alias:
        # service will be imported as postgres-service.backend.svc.mesh-two-imports.local
        namespace: backend
        name: postgres-service
```

Once imported, the service should appear in the Imported Services List:

```json
$ oc get importedserviceset.federation.maistra.io/mesh-two -n mesh-one -o jsonpath='{.status}'|jq .
{
  "importedServices": [
    {
      "exportedName": "postgres-service.backend.svc.mesh-one-exports.local",
      "localService": {
        "hostname": "postgres-service.backend.svc.mesh-two-imports.local",
        "name": "postgres-service",
        "namespace": "backend"
      }
    }
  ]
}
```

With the imported service name available locally, the frontend application may be deployed:

```bash
# deploy the application
$ kustomize build --reorder none servicemesh/8.federation/workload/quarkus-app-mesh-one | oc apply -f -
```

Now for this deployment to work, a couple objects need to be created in the frontend-namespace project:

```bash
$ for i in istio-gateway quarkus-virtualservice quarkus-destinationrule; do
    oc apply -f servicemesh/8.federation/federated-services/mesh-one/$i.yaml -n frontend-namespace
done
```

## Related Guides

- RESTEasy JAX-RS ([guide](https://quarkus.io/guides/rest-json)): REST endpoint framework implementing JAX-RS and more
- TektonCD ([docs](https://docs.openshift.com/container-platform/4.9/cicd/pipelines/understanding-openshift-pipelines.html)): Openshift Pipelines Documentation
- Istio.io ([docs](https://istio.io/latest/docs/)): Upstream Istio API Docs
- ServiceMesh ([docs](https://docs.openshift.com/container-platform/4.9/service_mesh/v2x/ossm-about.html)): Openshift ServiceMesh specific documentation

###  Notes

Container image build pipelines currently require the privileged SCC to be attached to the 'pipeline' ServiceAccount in order to successfully run:

```bash
oc adm policy add-scc-to-user privileged system:serviceaccount:<target_namespace>:pipeline
```
