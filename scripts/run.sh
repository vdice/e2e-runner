#!/bin/bash

source ./config.sh
source ./debug.sh
source ./deis.sh
source ./e2e.sh
source ./helm.sh
source ./lease.sh

if [ ! -d ${DEIS_LOG_DIR} ]; then
  mkdir -p "${DEIS_LOG_DIR}"
fi

# Get a k8s cluster lease
lease

# Get node information
kubectl get nodes

# Get Helm up to date and checkout branch if needed
echo "Adding repo ${HELM_REMOTE_REPO}"
helmc repo add deis "${HELM_REMOTE_REPO}"
echo "Get helm up to date"
helmc up
cd $DEIS_CHART_HOME
echo "Checking out ${WORKFLOW_BRANCH} for ${WORKFLOW_CHART}"
git checkout $WORKFLOW_BRANCH
helmc fetch "deis/${WORKFLOW_CHART}"

# Clean cluster if needed
echo "Cleaning cluster if needed"
clean_cluster

# Install $WORKFLOW_CHART
echo "Generate manifests from templates"
helmc generate "${WORKFLOW_CHART}"
echo "Installing chart ${WORKFLOW_CHART}"
helmc install "${WORKFLOW_CHART}" &> /dev/null

# Dump log data to stdout
echo "Running kubectl describe pods and piping the output to ${DEIS_DESCRIBE}"
kubectl describe ns,svc,pods,rc,daemonsets --namespace=deis > "${DEIS_DESCRIBE}" 2> /dev/null
print-out-running-images

# Healthcheck Deis
echo "Health check deis until its completely up!"
deis_healthcheck
echo "Use http://grafana.$(get-router-ip).nip.io/ to monitor the e2e run"

# Install e2e chart
echo "Installing workflow-e2e chart ${WORKFLOW_E2E_CHART}"
cd $DEIS_CHART_HOME
echo "Checking out ${WORKFLOW_E2E_BRANCH} for ${WORKFLOW_E2E_CHART}"
git checkout "${WORKFLOW_E2E_BRANCH}"
helmc fetch "deis/${WORKFLOW_E2E_CHART}"
helmc generate "${WORKFLOW_E2E_CHART}"
helmc install "${WORKFLOW_E2E_CHART}" &> /dev/null

# Capture e2e run test output
tail_logs_from_e2e_pod
podExitCode=$?

#Collect artifacts
retrive-artifacts

#Clean up
delete_lease
exit $(( ${podExitCode} + $? ))
