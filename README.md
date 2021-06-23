# GKE and CloudSQL With 0 Stored Credentials

A Google Cloud demo using Workload Identity on GKE and IAM Account Login for Cloud SQL to
provide secure auth for GKE workloads. There are no stored credentials (key
files or GKE/managed secrets) in the entire workflow.

## Deploying

* have a logged in `gcloud` instance with an `Owner` role. This is likely not a
  hard requirement, but creating a Project and enabling APIs needs significant
  capabilities. If you don't have access to an account with these capabilities
  you can use `bootstrap.sh` as a reference to get this done and edit the script
  itself.
* clone this repo and `cd` to the checked out code
* copy `envars.sample` to `envars` and add the needed configuration.
  ```
  export PROJECT=my-project
  export REGION=us-central1
  export ZONE=us-central1-a
  export APP_NAME=sample
  export DB_USER=postgres 
  export DB_PASS=k8FixjcynEFF7cvB
  export GCP_BILLING_ACCT=XXXXX-XXXXX-XXXXX
  export GCP_FOLDER=XXXXXXXXXXXX
  ```
  * `PROJECT` - the name of the Project you want to create
  * `REGION` - the Region you want to deploy to
  * `ZONE` - the Zone in the Region you want to use
  * `APP_NAME` - the name you want to call the sample app. It defaults to
    `sample`
  * `DB_USER` - this should remain `postgres`
  * `DB_PASS` - a password for `$DB_USER`
  * `GCP_BILLING_ACCT` - your GCP billing account to link with your Project
  * `GCP_FOLDER` - Folder to put your Project in. This is my default behavior.
    You may need to edit this depending on how your organize your GCP Projects.
* Run `bootstrap.sh
  ```
  ./bootstrap.sh
  ```

That's it! The process takes a little while (enabling APIs, creating the Cloud
SQL instance and dpeloying GKE are the primary time sinks). 

The following output is created to signify success: 

```
BOOTSTRAP COMPLETE: Google Cloud Artifacts Created:

 GCP Project: jduncan-wi-12
 Google Cloud API: compute.googleapis.com
 Google Cloud API: sql-component.googleapis.com
 Google Cloud API: sqladmin.googleapis.com
 Google Cloud API: container.googleapis.com
 Google Cloud API: artifactregistry.googleapis.com
 Google Cloud API: cloudbuild.googleapis.com
 Google Cloud API: servicenetworking.googleapis.com
 Cloud SQL Instace: sample-db
 Cloud SQL User: sample-psql-gsa@jduncan-wi-12.iam
 Cloud SQL Database: sample-db
 GKE Cluster: sample-gke
 IAM Service Account: sample-gsa
 IAM Service Account: sample-psql-gsa
 Artifact Registry: sample-repo
 VPC Peering Address Space: google-managed-services-default
 ```

## Testing and Using

The demo doesn't set up Ingress for the service. To see the app live use
`kubectl` port-forwarding. The bootstrap script sets the context for the GKE
cluster to your active context, so the following command should work cleanly. 

```
source envars
kubectl port-forward --namespace $APP_NAME $(kubectl get pod --namespace $APP_NAME --selector="app=$APP_NAME-app" --output jsonpath='{.items[0].metadata.name}') 8080:8080
```

Then just browse to port `8080` on your local machine! 

## Cleaning Up

Running `cleanup.sh` turns down the entire Project you've just created.

## Issues

Please feel free to open an issue, send me a message, or whatever is expedient.
