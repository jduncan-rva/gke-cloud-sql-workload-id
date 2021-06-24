#! /usr/bin/env bash
# License: Apache2

source envars

ARTIFACTS=( "\n\n\nBOOTSTRAP COMPLETE: Google Cloud Artifacts Created:\n\n" )

create_project () {
# Creates a project and associates it with a billing account

  echo "STEP 0: Creating Project from envars"
  gcloud projects create $PROJECT \
  --set-as-default \
  --folder $GCP_FOLDER

  gcloud beta billing projects link $PROJECT \
  --billing-account $GCP_BILLING_ACCT

  ARTIFACTS+=("GCP Project: $PROJECT\n")

  gcloud config set compute/region $REGION
}

enable_apis () {
  # Makes sure the proper APIs are enable for your Project

  echo "STEP 1: Enabling Required APIs"

  SERVICES=("compute sql-component sqladmin container artifactregistry cloudbuild servicenetworking")
  
  for api in ${SERVICES[@]}
    do
      gcloud services enable $api.googleapis.com -q
      ARTIFACTS+=("Google Cloud API: $api.googleapis.com\n")
    done
}

create_psql () {
  # Creates a Cloud SQL Postgres 13 instance 

  echo "STEP 2: Creating $APP_NAME-db Postgres 13 instance"
  gcloud sql instances create $APP_NAME-db --database-version POSTGRES_13 \
  --cpu 4 --memory 26GB --storage-size 100GB \
  --root-password $DB_PASS \
  --database-flags cloudsql.iam_authentication=on \
  --availability-type ZONAL \
  --region us-central1

  ARTIFACTS+=("Cloud SQL Instace: $APP_NAME-db\n")

  gcloud sql users create $APP_NAME-psql-gsa@$PROJECT.iam \
  --type cloud_iam_service_account \
  --instance $APP_NAME-db

  ARTIFACTS+=("Cloud SQL User: $APP_NAME-psql-gsa@$PROJECT.iam\n")

  gcloud sql databases create $APP_NAME-app --instance $APP_NAME-db

  ARTIFACTS+=("Cloud SQL Database: $APP_NAME-db\n")
}

create_psql_sa () {
  # Creates a service account to use with Workload Identity

  echo "STEP 4: Creating Workload Identity IAM account for Cloud SQL"
  gcloud iam service-accounts create $APP_NAME-psql-gsa \
  --display-name "PSQL Auth Proxy SA"

  ARTIFACTS+=("IAM Service Account: $APP_NAME-psql-gsa\n")

  gcloud projects add-iam-policy-binding $PROJECT \
  --member serviceAccount:$APP_NAME-psql-gsa@$PROJECT.iam.gserviceaccount.com \
  --role roles/cloudsql.client --role roles/cloudsql.instanceUser

  gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:$PROJECT.svc.id.goog[$APP_NAME/$APP_NAME-psql-ksa]" \
  $APP_NAME-psql-gsa@$PROJECT.iam.gserviceaccount.com

}

create_gke_sa () {
  # Creates a service account to use with Workload Identity

  echo "STEP 3: Creating Workload Identity IAM account"
  gcloud iam service-accounts create $APP_NAME-gsa \
  --display-name "Workload Identity SA"

  ARTIFACTS+=("IAM Service Account: $APP_NAME-gsa\n")
  
  gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:$PROJECT.svc.id.goog[$APP_NAME/$APP_NAME-ksa]" \
  $APP_NAME-gsa@$PROJECT.iam.gserviceaccount.com
}

deploy_gke () {
  # Deploys GKE with Workload Identity enabeld

  echo "STEP 5: Deploying $APP_NAME-gke GKE cluster"
  gcloud container clusters create $APP_NAME-gke \
  --scopes "https://www.googleapis.com/auth/userinfo.email","cloud-platform" \
  --zone $ZONE \
  --workload-pool $PROJECT.svc.id.goog \
  --machine-type n2-standard-8 \
  --num-nodes 4 

  ARTIFACTS+=("GKE Cluster: $APP_NAME-gke\n")

  gcloud container clusters get-credentials $APP_NAME-gke
  kubectx $APP_NAME-gke=.
}

create_artifact_registry () {
  # Creates an artifact registry for Cloud Build to use

  echo "STEP 8: Creating application Artifact Registry"
  gcloud artifacts repositories create $APP_NAME-repo \
  --repository-format=docker \
  --location=$REGION \
  --description="Image Repository"

  ARTIFACTS+=("Artifact Registry: $APP_NAME-repo\n")
}

generate_yaml_files () {
  # Creates YAML files with environment variables popualted

  echo "STEP 6: Generating YAML files from templates"
  for template in $(ls kube/*.template); do
    envsubst < ${template} > ${template%.*}
  done

  for template in $(ls src/*.template); do
    envsubst < ${template} > ${template%.*}
  done

  for template in $(ls *.template); do
    envsubst < ${template} > ${template%.*}
  done
}

build_app_image () {
  # Builds an app image with Cloud Build

  echo "STEP 9: Building application image with Cloud Build"
  gcloud builds submit --config cloudbuild.yaml
}

import_sql_data () {
  # Populates Postgres with sample data

  echo "STEP 7: Import SQL data into $APP_NAME-db Cloud SQL instance"
  gsutil mb gs://sqldata-$PROJECT-$APP_NAME
  gsutil cp clubdata.sql gs://sqldata-$PROJECT-$APP_NAME
  # gsutil cp grants.sql gs://sqldata-$PROJECT-$APP_NAME

  SQL_SVC_ACCT=$(gcloud sql instances describe $APP_NAME-db --format 'value( serviceAccountEmailAddress)')
  
  gcloud projects add-iam-policy-binding $PROJECT \
  --member serviceAccount:$SQL_SVC_ACCT \
  --role roles/storage.objectViewer

  gcloud sql import sql $APP_NAME-db gs://sqldata-$PROJECT-$APP_NAME/clubdata.sql --database $APP_NAME-app 
  
  gcloud sql import sql $APP_NAME-db gs://sqldata-$PROJECT-$APP_NAME/grants.sql --database $APP_NAME-app
}

configure_gke () {
  # Deploys workloads to GKE

  echo "STEP 10: Deploying workloads to $APP_NAME-gke GKE cluster"
  kubectx $APP_NAME-gke
  kubectl apply -n $APP_NAME -f kube/namespace.yaml
  kubectl apply -n $APP_NAME -f kube/serviceaccounts.yaml
  kubectl apply -n $APP_NAME -f kube/wi-test.yaml
  kubectl apply -n $APP_NAME -f kube/wi-test-no-sa.yaml
  kubectl apply -n $APP_NAME -f kube/app-deployment.yaml
}

configure_service_peering () {
  # sets up VPC > Service peering so GKE can talk to Cloud SQL

  echo "STEP 11: Configuring VPC peering to Cloud SQL"
  gcloud compute addresses create google-managed-services-default \
  --global \
  --purpose VPC_PEERING \
  --prefix-length 24 \
  --network default

  ARTIFACTS+=("VPC Peering Address Space: google-managed-services-default\n")

  echo "Creating VPC peering for Cloud SQL. This may take a few minutes."
  gcloud services vpc-peerings connect \
  --service servicenetworking.googleapis.com \
  --ranges google-managed-services-default \
  --network default 
}

completion_string () {
  # Loops through all of the items documented in the ARTIFACTS array

  echo -e ${ARTIFACTS[@]}

}

create_project
enable_apis
create_psql
deploy_gke
create_gke_sa
create_psql_sa 
generate_yaml_files
import_sql_data
create_artifact_registry
build_app_image
configure_gke
configure_service_peering
completion_string
