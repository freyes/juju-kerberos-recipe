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
juju ssh $IPA_ADDRESS "sudo touch /etc/krb5kdc/kadm5.acl && sudo systemctl restart krb5-admin-server.service"

# test the IPA was configured correctly
juju ssh $IPA_ADDRESS "sudo kdestroy"
juju ssh $IPA_ADDRESS "echo $IPA_PASSWORD | sudo kinit admin && \
     sudo klist && \
     sudo ipa user-find admin"

juju deploy --overlay overlay_keystone.yaml ./lab-bundle.yaml
juju wait
KEYSTONE_IP=$(juju run --unit keystone/leader unit-get public-address)
KEYSTONE_HOST="$(echo $KEYSTONE_IP | sed 's/\./-/g').$MAAS_DOMAIN"

# register keystone unit and get keytab
juju ssh $IPA_ADDRESS "sudo ipa host-find --hostname=$KEYSTONE_HOST || sudo ipa host-add $KEYSTONE_HOST --ip-address=$KEYSTONE_IP"
juju ssh $IPA_ADDRESS "sudo ipa service-find --principal=HTTP/$KEYSTONE_HOST || sudo ipa service-add HTTP/$KEYSTONE_HOST"
juju ssh $IPA_ADDRESS "sudo ipa-getkeytab -p HTTP/$KEYSTONE_HOST -k /tmp/keystone.keytab && sudo chmod +r /tmp/keystone.keytab"
juju scp $IPA_ADDRESS:/tmp/keystone.keytab ./


# user-add john
juju ssh $IPA_ADDRESS "sudo ipa user-find john || sudo ipa user-add john --first=John --last=Doe"
juju ssh $IPA_ADDRESS "echo ubuntu11 | sudo ipa user-mod john --password"
juju ssh $IPA_ADDRESS "sudo ipa user-mod john --state k8s" || echo "already set"

# user-add jane
juju ssh $IPA_ADDRESS "sudo ipa user-find jane || sudo ipa user-add jane --first=Jane --last=Fonda"
juju ssh $IPA_ADDRESS "echo ubuntu11 | sudo ipa user-mod jane --password"
juju ssh $IPA_ADDRESS "sudo ipa user-mod jane --state k8s" || echo "already set"

# -- add keystone-kerberos now that we have the keytab.
sed "s/__LDAP_SERVER__/$IPA_ADDRESS/g" overlay_kerberos.yaml.tpl > overlay_kerberos.yaml
juju deploy --overlay ./overlay_kerberos.yaml --overlay overlay_keystone.yaml ./lab-bundle.yaml

juju wait

# generate kerberos configuration
sed "s/__IPA_HOSTNAME__/$IPA_HOSTNAME/g" krb5.conf.tpl > krb5.conf
sed -i "s/__REALM__/$REALM/g" krb5.conf

cat <<EOF> john.rc
export OS_USERNAME=john
export OS_PASSWORD=ubuntu11
export OS_DOMAIN_NAME=k8s
export OS_PROJECT_NAME=k8s
export OS_REGION_NAME=RegionOne
export OS_PROJECT_DOMAIN_NAME=k8s
export OS_USER_DOMAIN_NAME=k8s
export OS_AUTH_URL=http://${KEYSTONE_HOST}:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF

cat <<EOF> john-krb.rc
export OS_PROJECT_NAME=k8s
export OS_REGION_NAME=RegionOne
export OS_DOMAIN_NAME=k8s
export OS_PROJECT_DOMAIN_NAME=k8s
export OS_USER_DOMAIN_NAME=k8s
export OS_AUTH_URL=http://${KEYSTONE_HOST}:5000/krb/v3
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_TYPE=v3kerberos
EOF

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

juju scp ./john.rc keystone/0:/home/ubuntu
juju scp ./john-krb.rc keystone/0:/home/ubuntu
juju scp ./admin.rc keystone/0:/home/ubuntu

set +x
echo -n "wait until keystone is up-n-running"
while ! curl -s -o /dev/null http://${KEYSTONE_HOST}:5000/v3
do
    echo -n '.'
    sleep 5
done
echo "done"
set -x

source ./admin.rc
openstack role list -f value -c Name | grep k8s-admins || openstack role create k8s-admins
openstack role list -f value -c Name | grep k8s-users  || openstack role create k8s-users
openstack role list -f value -c Name | grep k8s-viewers || openstack role create k8s-viewers
openstack project list --domain k8s -f value -c Name | grep k8s || openstack project create --domain k8s k8s

## add a role to the users in a the k8s project/domain

#making john a member of k8s project and k8s-user of k8s domain
USER_ID=$(openstack user show --domain k8s -f value -c id john)
ROLE_ID=$(openstack role show -f value -c id k8s-users)
openstack role add --project k8s --user $USER_ID  $ROLE_ID || echo "already added"

# making jane Admin of k8s project and k8s-admins of k8s domain
USER_ID=$(openstack user show --domain k8s -f value -c id jane)
ROLE_ID=$(openstack role show -f value -c id k8s-admins)
openstack role add --project k8s --user $USER_ID  $ROLE_ID || echo "already added"

juju deploy --overlay ./overlay_kerberos.yaml --overlay overlay_keystone.yaml --overlay ./overlay_k8s.yaml ./lab-bundle.yaml
juju wait

juju scp kubernetes-master/0:config kube.config


# kube-keystone.sh takes a while to be generated.
set +x
echo -n "trying to get kube-keystone.sh from kubernetes-master/0"
while ! juju scp kubernetes-master/0:kube-keystone.sh kube-keystone.sh 2>&1 >/dev/null
do
  echo -n "."
  sleep 5
done
echo "done"

echo "to get a ticket from kerberos use:"
echo "    sudo apt install krb5-user"
echo "    KRB5_CONFIG=./krb5.conf kinit <USERNAME>"
echo "to use kubectl:"
echo "    sudo snap install --edge client-keystone-auth"
echo "    KUBECONFIG=kube.config kubectl get pods"
echo "to generate a token to use in the dashboard (see LP: #1893214):"
echo "    source john.rc"
echo "    ./gen-token.sh"

notify-send -u critical "$0: deployment ready" || echo "deployment ready"
