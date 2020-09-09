[libdefaults]
	default_realm = __REALM__
	kdc_timesync = 1
	ccache_type = 4
	forwardable = true
	proxiable = true

[realms]
	__REALM__ = {
		kdc = __IPA_HOSTNAME__
		admin_server = __IPA_HOSTNAME__
	}
[domain_realm]
        .__REALM__ = __REALM__
         __REALM__ = __REALM__
