#!/bin/bash
#
# deploy noverant charts to noverant.github.io
#

set -o errexit
set -o pipefail

CHART_DIR="charts"
CHART_REPO="git@github.com:noverant/noverant.github.io.git"
REPO_DIR="noverant.github.io"
REPO_ROOT="$(git rev-parse --show-toplevel)"
TMP_DIR="tmp"

if [ "${CIRCLECI}" == 'true' ] && [ -z "${CIRCLE_PULL_REQUEST}" ]; then

  # get noverant.github.io
  test -d "${REPO_ROOT}"/"${REPO_DIR}" && rm -rf "${REPO_ROOT:=?}"/"${REPO_DIR:=?}"
  git clone "${CHART_REPO}" "${REPO_ROOT}"/"${REPO_DIR}"

  # get not builded charts
  while read -r FILE; do
    echo "check file ${FILE}"
    if [ ! -f "${REPO_ROOT}/${REPO_DIR}/$(yq r - name < "${FILE}")-$(yq r - version < "${FILE}").tgz" ]; then
      echo "append chart ${FILE}"
      CHARTS="${CHARTS} $(yq r - name < "${FILE}")"
    fi
  done < <(find "${REPO_ROOT}/${CHART_DIR}" -maxdepth 2 -mindepth 2 -type f -name "[Cc]hart.yaml")

  if [ -z "${CHARTS}" ]; then
    echo "no chart changes... so no chart build and upload needed... exiting..."
    exit 0
  fi

  # set original file dates
  (
  cd "${REPO_ROOT}"/"${REPO_DIR}" || exit
  while read -r FILE; do
    ORG_FILE_TIME=$(git log --pretty=format:%cd --date=format:'%y%m%d%H%M' "${FILE}" | tail -n 1)
    echo "set original time ${ORG_FILE_TIME} to ${FILE}"
    touch -c -t "${ORG_FILE_TIME}" "${FILE}"
  done < <(git ls-files)
  )

  # preserve dates in index.yaml by moving old charts and index out of the repo before packaging the new version
  mkdir -p "${REPO_ROOT}"/"${TMP_DIR}"
  mv "${REPO_ROOT}"/"${REPO_DIR}"/index.yaml "${REPO_ROOT}"/"${TMP_DIR}" || true
  mv "${REPO_ROOT}"/"${REPO_DIR}"/*.tgz "${REPO_ROOT}"/"${TMP_DIR}"

  #add helm repos
  helm repo add noverant https://noverant.github.io
  helm repo update

  # build helm dependencies for all charts
  find "${REPO_ROOT}"/"${CHART_DIR}" -mindepth 1 -maxdepth 1 -type d -exec helm dependency build {} \;

  # package only changed charts
  for CHART in ${CHARTS}; do
    echo "building ${CHART} chart..."
    helm package "${REPO_ROOT}"/"${CHART_DIR}"/"${CHART}" --destination "${REPO_ROOT}"/"${REPO_DIR}"
  done

  # Create index and merge with previous index which contains the non-changed charts
  helm repo index --merge "${REPO_ROOT}"/"${TMP_DIR}"/index.yaml --url https://"${REPO_DIR}" "${REPO_ROOT}"/"${REPO_DIR}"

  # move old charts back into git repo
  mv "${REPO_ROOT}"/"${TMP_DIR}"/*.tgz "${REPO_ROOT}"/"${REPO_DIR}"

  # push changes to github
  cd "${REPO_ROOT}"/"${REPO_DIR}"
  git config --global user.email "ci@noverant-robot.com"
  git config --global user.name "noverant-ci-bot"
  git add --all .
  git commit -m "push noverant charts via circleci build nr: ${CIRCLE_BUILD_NUM}"
  git push --set-upstream origin master
else
  echo "skipped deploy as only merged pr in master is deployed..."
fi
