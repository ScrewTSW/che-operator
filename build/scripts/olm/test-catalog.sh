#!/bin/bash
#
# Copyright (c) 2019-2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#

set -e

OPERATOR_REPO=$(dirname "$(dirname "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")")")
source "${OPERATOR_REPO}/build/scripts/oc-tests/oc-common.sh"

init() {
  unset NAMESPACE
  unset OPERATOR_NAMESPACE
  unset VERBOSE
  unset CATALOG_IMAGE
  unset CHANNEL

  while [[ "$#" -gt 0 ]]; do
    case $1 in
      '--channel'|'-c') CHANNEL="$2"; shift 1;;
      '--che-namespace'|'-n') NAMESPACE="$2"; shift 1;;
      '--operator-namespace'|'-o') OPERATOR_NAMESPACE="$2"; shift 1;;
      '--catalog-image'|'-i') CATALOG_IMAGE="$2"; shift 1;;
      '--verbose'|'-v') VERBOSE=1;;
      '--help'|'-h') usage; exit;;
    esac
    shift 1
  done

  [[ ! ${NAMESPACE} ]] && NAMESPACE="eclipse-che"
  [[ ! ${OPERATOR_NAMESPACE} ]] && NAMESPACE="openshift-operators"
  if [[ ! ${CHANNEL} ]] || [[ ! ${CATALOG_IMAGE} ]]; then usage; exit 1; fi
}

usage () {
  echo "Deploy Eclipse Che from a catalog."
  echo
	echo "Usage:"
	echo -e "\t$0 -i CATALOG_IMAGE -c CHANNEL [-n NAMESPACE] [--verbose]"
  echo
  echo "OPTIONS:"
  echo -e "\t-i,--catalog-image       Catalog image"
  echo -e "\t-c,--channel=next|stable Olm channel to deploy Eclipse Che from"
  echo -e "\t-n,--che-namespace       [default: eclipse-che] Kubernetes namespace to deploy Eclipse Che operands into"
  echo -e "\t-o,--operator-namespace  [default: openshift-operators] Kubernetes namespace to deploy Eclipse Che operator into"
  echo -e "\t-v,--verbose             Verbose mode"
  echo
	echo "Example:"
	echo -e "\t$0 -i quay.io/eclipse/eclipse-che-olm-catalog:next -c next"
	echo -e "\t$0 -i quay.io/eclipse/eclipse-che-olm-catalog:test -c stable"
}

run() {
  make create-namespace NAMESPACE="${NAMESPACE}" VERBOSE=${VERBOSE}
  make create-namespace NAMESPACE="${OPERATOR_NAMESPACE}" VERBOSE=${VERBOSE}
  make create-operatorgroup NAME="eclipse-che" NAMESPACE="${OPERATOR_NAMESPACE}" VERBOSE=${VERBOSE}
  make create-catalogsource NAME="${ECLIPSE_CHE_CATALOG_SOURCE_NAME}" IMAGE="${CATALOG_IMAGE}" VERBOSE=${VERBOSE} NAMESPACE="openshift-marketplace"

  discoverEclipseCheBundles "${CHANNEL}"

  if [[ "${LATEST_VERSION}" == "null" ]]; then
    echo "[ERROR] CatalogSource does not contain any bundles."
    exit 1
  fi

  if [[ ${CHANNEL} == "next" ]]; then
    make install-devworkspace CHANNEL=next OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE}" VERBOSE=${VERBOSE}
  else
    make install-devworkspace CHANNEL=fast OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE}" VERBOSE=${VERBOSE}
  fi

  make create-subscription \
    NAME="${ECLIPSE_CHE_SUBSCRIPTION_NAME}" \
    NAMESPACE="${OPERATOR_NAMESPACE}" \
    PACKAGE_NAME="${ECLIPSE_CHE_PACKAGE_NAME}" \
    CHANNEL="${CHANNEL}" \
    SOURCE="${ECLIPSE_CHE_CATALOG_SOURCE_NAME}" \
    SOURCE_NAMESPACE="openshift-marketplace" \
    INSTALL_PLAN_APPROVAL="Auto" \
    VERBOSE=${VERBOSE}
  make wait-pod-running NAMESPACE="${OPERATOR_NAMESPACE}" SELECTOR="app.kubernetes.io/component=che-operator"
  getCheClusterCRFromInstalledCSV | oc apply -n "${NAMESPACE}" -f -
  make wait-eclipseche-version VERSION="$(getCheVersionFromInstalledCSV)" NAMESPACE=${NAMESPACE} VERBOSE=${VERBOSE}
}

init "$@"
[[ ${VERBOSE} == 1 ]] && set -x

pushd "${OPERATOR_REPO}" >/dev/null
run
popd >/dev/null

echo "[INFO] Done"

