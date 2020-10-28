applications:
  keystone-kerberos:
    charm: cs:keystone-kerberos
    options:
      kerberos-realm: "__REALM__"
      kerberos-server: "__LDAP_SERVER__"
    resources:
      keystone_keytab: "./keystone.keytab"
  keystone-ldap:
    charm:  cs:keystone-ldap
    num_units: 0
    options:
      ldap-server: "ldap://__LDAP_SERVER__"
      ldap-user: "uid=admin,cn=users,cn=compat,__LDAP_SUFFIX__"
      ldap-password: "__LDAP_PASSWORD__"
      ldap-suffix: "cn=compat,__LDAP_SUFFIX__"
      ldap-readonly: true
      domain-name: "k8s"
      ldap-config-flags: "{
          user_tree_dn: 'cn=users,cn=accounts,__LDAP_SUFFIX__',
          query_scope: sub,
          user_objectclass: person,
          user_name_attribute: uid,
          user_default_project_id_attribute: st,
          group_tree_dn: 'cn=groups,cn=accounts,__LDAP_SUFFIX__',
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
