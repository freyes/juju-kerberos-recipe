applications:
  keystone-kerberos:
    charm: cs:keystone-kerberos
    options:
      kerberos-realm: "LAB.MAAS"
      kerberos-server: "__LDAP_SERVER__"
    resources:
      keystone_keytab: "./keystone.keytab"
  keystone-ldap:
    charm:  cs:keystone-ldap
    num_units: 0
    options:
      ldap-server: "ldap://__LDAP_SERVER__"
      ldap-user: "uid=admin,cn=users,cn=compat,dc=lab,dc=maas"
      ldap-password: "ubuntu11"
      ldap-suffix: "cn=users,cn=compat,dc=lab,dc=maas"
      ldap-readonly: true
      domain-name: "k8s"
relations:
 - [keystone, keystone-kerberos]
 - [keystone, keystone-ldap]
