#!/bin/bash -ex

_USERNAME=$1
FIRST_NAME=$2
LAST_NAME=$3

juju run --unit ipa/leader "sudo ipa user-find $_USERNAME || sudo ipa user-add $_USERNAME --first=$FIRST_NAME --last=$LAST_NAME"
juju run --unit ipa/leader "echo ubuntu11 | sudo ipa user-mod $_USERNAME --password"
juju run --unit ipa/leader "sudo ipa user-mod $_USERNAME --state k8s" || echo "already set"
