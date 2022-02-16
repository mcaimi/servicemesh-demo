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
Another instance of the same application (found in this repository) acts as "v2". The application has been rebased to Quarkus 2.4 and the frontend has been updated.

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
$ kustomize build servicemesh/1.operator | oc apply -f -
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


## Related Guides

- RESTEasy JAX-RS ([guide](https://quarkus.io/guides/rest-json)): REST endpoint framework implementing JAX-RS and more
- TektonCD ([docs](https://docs.openshift.com/container-platform/4.9/cicd/pipelines/understanding-openshift-pipelines.html)): Openshift Pipelines Documentation
- Istio.io ([docs](https://istio.io/latest/docs/)): Upstream Istio API Docs
- ServiceMesh ([docs](https://docs.openshift.com/container-platform/4.9/service_mesh/v2x/ossm-about.html)): Openshift ServiceMesh specific documentation

###  Notes

Container image build pipelines currently require the privileged SCC to be attached to the 'pipeline' ServiceAccount in order to successfully run:

```bash
oc adm add-scc-to-user privileged -z system:serviceaccount:istio-demo:pipeline
```

