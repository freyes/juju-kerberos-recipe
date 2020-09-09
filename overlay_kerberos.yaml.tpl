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
      ldap-suffix: "cn=compat,dc=lab,dc=maas"
      ldap-readonly: true
      domain-name: "k8s"
      ldap-config-flags: "{
          user_tree_dn: 'cn=users,cn=accounts,dc=lab,dc=maas',
          query_scope: sub,
          user_objectclass: person,
          user_name_attribute: uid,
          group_tree_dn: 'cn=groups,cn=accounts,dc=lab,dc=maas',
          group_objectclass: posixgroup,
          group_id_attribute: cn,
          group_name_attribute: cn,
          user_allow_create: False,
          user_allow_update: False,
          user_allow_delete: False,
          }"
relations:
 - [keystone, keystone-kerberos]
 - [keystone, keystone-ldap]
