#!/bin/bash -ex
#
# This script relies on a model named "kerberos" that contains a ipa server already configured.
#

IPA_UNIT=ipa/1

juju deploy ./lab-bundle.yaml
juju wait
KEYSTONE_IP=$(juju run --unit keystone/leader unit-get public-address)
HOST="$(echo $KEYSTONE_IP | sed 's/\./-/g').lab.maas"

# --- register keystone host in IPA
set JUJU_MODEL=kerberos
IP_ADDRESS=$(juju ssh ipa/1 "dig +short $HOST" | tr -d '\r')

juju ssh $IPA_UNIT "sudo ipa host-add $HOST --ip-address=$IP_ADDRESS"
juju ssh $IPA_UNIT "sudo ipa service-add HTTP/$HOST"
juju ssh $IPA_UNIT "sudo ipa-getkeytab -p HTTP/$HOST -k /tmp/keystone.keytab"
juju ssh $IPA_UNIT "sudo chmod +r /tmp/keystone.keytab"
juju scp $IPA_UNIT:/tmp/keystone.keytab ./
unset JUJU_MODEL

# -- add keystone-kerberos now that we have the keytab.
juju deploy --overlay ./overlay_kerberos.yaml ./lab-bundle.yaml

cat <<EOF> k8s-user.rc
export OS_USERNAME=admin
export OS_PASSWORD=openstack
export OS_PROJECT_NAME=admin
export OS_REGION_NAME=RegionOne
export OS_PROJECT_DOMAIN_NAME=admin_domain
export OS_USER_DOMAIN_NAME=admin_domain
export OS_AUTH_URL=http://${HOST}:5000/krb/v3
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_TYPE=v3kerberos
EOF

juju scp ./k8s-user.rc keystone/0:/home/ubuntu
