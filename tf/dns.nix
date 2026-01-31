{ lib, ... }:
let
  # Records created for every zone
  shared_records = domain: {
    autoconfig = {
      name = "autoconfig";
      type = "CNAME";
      data = "autoconfig.migadu.com.";
    };
    migadu_dkim1 = {
      name = "key1._domainkey";
      type = "CNAME";
      data = "key1.${domain}._domainkey.migadu.com.";
    };
    migadu_dkim2 = {
      name = "key2._domainkey";
      type = "CNAME";
      data = "key2.${domain}._domainkey.migadu.com.";
    };
    migadu_dkim3 = {
      name = "key3._domainkey";
      type = "CNAME";
      data = "key3.${domain}._domainkey.migadu.com.";
    };
    migadu_mx1 = {
      name = "";
      type = "MX";
      data = "aspmx1.migadu.com.";
      priority = 10;
    };
    migadu_mx2 = {
      name = "";
      type = "MX";
      data = "aspmx2.migadu.com.";
      priority = 20;
    };
    migadu_ffa_mx1 = {
      name = "*";
      type = "MX";
      data = "aspmx1.migadu.com.";
      priority = 10;
    };
    migadu_ffa_mx2 = {
      name = "*";
      type = "MX";
      data = "aspmx2.migadu.com.";
      priority = 20;
    };
    migadu_dmarc = {
      name = "_dmarc";
      type = "TXT";
      data = "v=DMARC1; p=quarantine;";
    };
    root_spf = {
      name = "";
      type = "TXT";
      data = "v=spf1 include:spf.migadu.com include:mailgun.org -all";
    };
  };

  mkRecords =
    prefix: zone:
    lib.mapAttrs' (name: value: {
      name = "${prefix}_${name}";
      value = {
        dns_zone = zone;
        ttl = 60;
      }
      // value;
    }) (shared_records zone);
in
{
  config.resource.scaleway_domain_record = lib.mkMerge [
    (mkRecords "lc" "lillecarl.com")
    (mkRecords "ps" "postspace.net")
    {
      lc_hello = {
        dns_zone = "lillecarl.com";
        name = "";
        type = "ALIAS";
        data = "lillecarl.github.io.";
      };
      lc_www = {
        dns_zone = "lillecarl.com";
        name = "www";
        type = "CNAME";
        data = "lillecarl.github.io.";
      };
      lc_hosted_email_verify = {
        dns_zone = "lillecarl.com";
        name = "";
        type = "TXT";
        data = "hosted-email-verify=apazwykz";
      };
      lc_keybase_verify = {
        dns_zone = "lillecarl.com";
        name = "";
        type = "TXT";
        data = "keybase-site-verification=MIzUFq3tfIr13fwTcb5N4a0XR-pSeMDc7WiuLfRJooc";
      };
      lc_pwned_verify = {
        dns_zone = "lillecarl.com";
        name = "";
        type = "TXT";
        data = "have-i-been-pwned-verification=49efa9d605cbd57ca56c54528ea26eb3";
      };
      lc_mailgun_dmarc = {
        dns_zone = "lillecarl.com";
        name = "_dmarc.mg";
        type = "TXT";
        data = "v=DMARC1; p=none; pct=100; fo=1; ri=3600; rua=mailto:fe15107c@dmarc.mailgun.org,mailto:835f4884@inbox.ondmarc.com; ruf=mailto:fe15107c@dmarc.mailgun.org,mailto:835f4884@inbox.ondmarc.com;";
      };
      lc_mg_spf = {
        dns_zone = "lillecarl.com";
        name = "mg";
        type = "TXT";
        data = "v=spf1 include:mailgun.org -all";
      };
      lc_mailgun_dkim1 = {
        dns_zone = "lillecarl.com";
        name = "pdk1._domainkey.mg";
        type = "CNAME";
        data = "pdk1._domainkey.9b0f04.dkim1.eu.mgsend.org.";
      };
      lc_mailgun_dkim2 = {
        dns_zone = "lillecarl.com";
        name = "pdk2._domainkey.mg";
        type = "CNAME";
        data = "pdk2._domainkey.9b0f04.dkim1.eu.mgsend.org.";
      };
    }
  ];
}
