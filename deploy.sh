#!/bin/bash -ex

MAAS_DOMAIN=lab.maas
MAAS_HOST=192.168.11.2
REALM=${MAAS_DOMAIN^^}
IPA_PASSWORD=ubuntu11

test -f vars.sh && . vars.sh

#deploying freeipa
juju deploy ./lab-bundle.yaml
juju wait

IPA_ADDRESS=$(juju run --unit ipa/leader unit-get public-address)
IPA_HOSTNAME=$(echo $IPA_ADDRESS | sed 's/\./-/g').$MAAS_DOMAIN

# create dns record in maas
ssh ubuntu@$MAAS_HOST "dig +short $IPA_HOSTNAME || maas admin dnsresources create fqdn=$IPA_HOSTNAME ip_addresses=$IPA_ADDRESS"

juju ssh $IPA_ADDRESS "dpkg -l freeipa-server || (sudo add-apt-repository -yu ppa:freyes/freeipa && \
                                                  sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install -yq freeipa-server)"
juju ssh $IPA_ADDRESS "test -f /home/ubuntu/.freeipa-installed || (sudo ipa-server-install -a $IPA_PASSWORD --hostname=$IPA_HOSTNAME -r $REALM -p ubuntu11 -n $MAAS_DOMAIN -U && touch /home/ubuntu/.freeipa-installed)"

# test the IPA was configured correctly
juju ssh $IPA_ADDRESS "echo $IPA_PASSWORD | sudo kinit admin && sudo klist && sudo ipa user-find admin"

read -t 30 -p "Resuming in 30s..." || echo "carry on"

juju deploy --overlay overlay_keystone.yaml ./lab-bundle.yaml
juju wait
KEYSTONE_IP=$(juju run --unit keystone/leader unit-get public-address)
KEYSTONE_HOST="$(echo $KEYSTONE_IP | sed 's/\./-/g').$MAAS_DOMAIN"

juju ssh $IPA_ADDRESS "sudo ipa host-find --hostname=$KEYSTONE_HOST || sudo ipa host-add $KEYSTONE_HOST --ip-address=$KEYSTONE_IP"
juju ssh $IPA_ADDRESS "sudo ipa service-find --principal=HTTP/$KEYSTONE_HOST || sudo ipa service-add HTTP/$KEYSTONE_HOST"
juju ssh $IPA_ADDRESS "sudo ipa-getkeytab -p HTTP/$KEYSTONE_HOST -k /tmp/keystone.keytab && sudo chmod +r /tmp/keystone.keytab"
juju ssh $IPA_ADDRESS "sudo ipa user-find john || sudo ipa user-add john --first=John --last=Doe"
juju ssh $IPA_ADDRESS "sudo ipa user-find jane || sudo ipa user-add jane --first=Jane --last=Fonda"
juju scp $IPA_ADDRESS:/tmp/keystone.keytab ./

# -- add keystone-kerberos now that we have the keytab.
sed "s/__LDAP_SERVER__/$IPA_ADDRESS/g" overlay_kerberos.yaml.tpl > overlay_kerberos.yaml
juju deploy --overlay ./overlay_kerberos.yaml --overlay overlay_keystone.yaml ./lab-bundle.yaml

juju wait

cat <<EOF> k8s-user.rc
export OS_USERNAME=admin
export OS_PASSWORD=openstack
export OS_PROJECT_NAME=admin
export OS_REGION_NAME=RegionOne
export OS_PROJECT_DOMAIN_NAME=admin_domain
export OS_USER_DOMAIN_NAME=admin_domain
export OS_AUTH_URL=http://${KEYSTONE_HOST}:5000/krb/v3
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_TYPE=v3kerberos
EOF

juju scp ./k8s-user.rc keystone/0:/home/ubuntu


cat <<EOF > admin.rc
export OS_AUTH_URL=http://${KEYSTONE_HOST}:5000/v3
export OS_IDENTITY_API_VERSION=3

export OS_USERNAME=admin
export OS_PASSWORD=openstack
export OS_PROJECT_NAME=admin
export OS_REGION_NAME=RegionOne
export OS_PROJECT_DOMAIN_NAME=admin_domain
export OS_USER_DOMAIN_NAME=admin_domain
EOF
juju scp ./admin.rc keystone/0:/home/ubuntu

source ./admin.rc
openstack role list --domain k8s -f value -c Name | grep k8s-admins || openstack role create --domain k8s k8s-admins
openstack role list --domain k8s -f value -c Name | grep k8s-users  || openstack role create --domain k8s k8s-users
openstack role list --domain k8s -f value -c Name | grep k8s-viewers || openstack role create --domain k8s k8s-viewers
openstack project list --domain k8s -f value -c Name | grep k8s || openstack project create --domain k8s k8s

juju deploy --overlay ./overlay_kerberos.yaml --overlay ./overlay_k8s.yaml ./lab-bundle.yaml
juju wait
notify-send -u critical "$0: deployment ready" || echo "deployment ready"
