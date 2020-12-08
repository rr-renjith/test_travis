#!/bin/bash

# Trigger a new Travis-CI job.

# Usage:
#   trigger-travis.sh [--pro] [--branch BRANCH] GITHUBID GITHUBPROJECT TRAVIS_ACCESS_TOKEN [MESSAGE]
# For example:
#   trigger-travis.sh typetools checker-framework `cat ~/private/.travis-access-token` "Trigger for testing"

if [ "$#" -lt 3 ] || [ "$#" -gt 7 ]; then
  echo "Wrong number of arguments $# to trigger-travis.sh; run like:"
  echo " trigger-travis.sh [--branch BRANCH] GITHUBID GITHUBPROJECT TRAVIS_ACCESS_TOKEN [MESSAGE]" >&2
  exit 1
fi

if [ "$1" = "--pro" ] ; then
  TRAVIS_URL=travis-ci.com
  shift
else
  TRAVIS_URL=travis-ci.org
fi

if [ "$1" = "--branch" ] ; then
  shift
  BRANCH="$1"
  shift
else
  BRANCH=master
fi

USER=$1
REPO=$2
TOKEN=$3
if [ $# -eq 4 ] ; then
    MESSAGE=",\"message\": \"$4\""
elif [ -n "$TRAVIS_REPO_SLUG" ] ; then
    MESSAGE=",\"message\": \"Triggered by upstream build of $TRAVIS_REPO_SLUG commit $(git log --oneline -n 1 HEAD)\""
else
    MESSAGE=""
fi

## For debugging:
echo "USER=$USER"
echo "REPO=$REPO"
echo "TOKEN=$TOKEN"
echo "MESSAGE=$MESSAGE"

body="{
\"request\": {
  \"branch\":\"$BRANCH\"
  $MESSAGE
}}"

# "%2F" creates a literal "/" in the URL, that is not interpreted as a
# segment or directory separator.
# creates a build request for cypress test

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Travis-API-Version: 3" \
  -H "Authorization: token ${TOKEN}" \
  -d "$body" \
  "https://api.${TRAVIS_URL}/repo/${USER}%2F${REPO}/requests" \
  > /tmp/travis-request-output.$$.txt

if grep -q '"@type": "error"' /tmp/travis-request-output.$$.txt; then
    exit 1
fi
if grep -q 'access denied' /tmp/travis-request-output.$$.txt; then
    exit 1
fi

BUILD_STARTED=false
BUILD_COMPLETED=false
BUILD_PATH="none"

BUILD_START_TIMEOUT=$((SECONDS+300))
BUILD_EXECUTION_TIMEOUT=$((SECONDS+3600))

while ! $BUILD_STARTED;
  do
    if [ $SECONDS -gt $BUILD_START_TIMEOUT ]; then
      echo "Timed out waiting for a response 'started' from automation build."
      exit 1
    fi

    curl -s \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Travis-API-Version: 3" \
    -H "Authorization: token ${TOKEN}" \
    "https://api.${TRAVIS_URL}/repo/${USER}%2F${REPO}/builds?state=started" \
    > /tmp/travis-build-state-output.$$.txt

    
    if grep -qP '"state":\s*"started"' /tmp/travis-build-state-output.$$.txt; then
      BUILD_STARTED=true
      BUILD_PATH=$(grep -Po '/build/[0-9]+' /tmp/travis-build-state-output.$$.txt)
    fi
    sleep 10s
  done

if  ! [[ $BUILD_PATH =~ /build/[0-9]+ ]]; then
  echo "Trigger sent to run Automation job but build id was not recorded"
  exit 1
fi

while ! $BUILD_COMPLETED;
  do
    if [ $SECONDS -gt $BUILD_EXECUTION_TIMEOUT ]; then
      echo "Automation build is taking longer than expected. Exiting the current build"
      exit 1
    fi

    curl -s \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -H "Travis-API-Version: 3" \
      -H "Authorization: token ${TOKEN}" \
      "https://api.${TRAVIS_URL}${BUILD_PATH}" \
      > /tmp/travis-build-state-output.$$.txt
    
    if grep -qP '"state":\s*"passed"' /tmp/travis-build-state-output.$$.txt; then
      BUILD_COMPLETED=true
    fi
    sleep 15s
  done

  if grep -qP '"state":\s*"failed"' /tmp/travis-build-state-output.$$.txt; then
      echo "Cypress tests failed. Check the downstream build logs/ Cypress Dashboard for test details."
      exit 1
  fi
