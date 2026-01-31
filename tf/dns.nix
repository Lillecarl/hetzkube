{ lib, ... }:
{
  config = {
    resource.scaleway_domain_record =
      let
        shared_records = {
          hello = {
            name = "";
            type = "ALIAS";
            data = "lillecarl.github.io.";
          };
          www = {
            name = "www";
            type = "CNAME";
            data = "lillecarl.github.io.";
          };
          autoconfig = {
            name = "autoconfig";
            type = "CNAME";
            data = "autoconfig.migadu.com.";
          };
          migadu_dkim1 = {
            name = "key1._domainkey";
            type = "CNAME";
            data = "key1.lillecarl.com._domainkey.migadu.com.";
          };
          migadu_dkim2 = {
            name = "key2._domainkey";
            type = "CNAME";
            data = "key2.lillecarl.com._domainkey.migadu.com.";
          };
          migadu_dkim3 = {
            name = "key3._domainkey";
            type = "CNAME";
            data = "key3.lillecarl.com._domainkey.migadu.com.";
          };
          mailgun_dkim1 = {
            name = "pdk1._domainkey.mg";
            type = "CNAME";
            data = "pdk1._domainkey.9b0f04.dkim1.eu.mgsend.org.";
          };
          mailgun_dkim2 = {
            name = "pdk2._domainkey.mg";
            type = "CNAME";
            data = "pdk2._domainkey.9b0f04.dkim1.eu.mgsend.org.";
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
          mailgun_dmarc = {
            name = "_dmarc.mg";
            type = "TXT";
            data = "v=DMARC1; p=none; pct=100; fo=1; ri=3600; rua=mailto:fe15107c@dmarc.mailgun.org,mailto:835f4884@inbox.ondmarc.com; ruf=mailto:fe15107c@dmarc.mailgun.org,mailto:835f4884@inbox.ondmarc.com;";
          };
          root_spf = {
            name = "";
            type = "TXT";
            data = "v=spf1 include:_spf.mx.cloudflare.net include:spf.migadu.com nclude:mailgun.org -all";
          };
          mg_spf = {
            name = "";
            type = "TXT";
            data = "v=spf1 include:mailgun.org -all";
          };
          hosted_email_verify = {
            name = "";
            type = "TXT";
            data = "hosted-email-verify=apazwykz";
          };
          keybase_verify = {
            name = "";
            type = "TXT";
            data = "keybase-site-verification=MIzUFq3tfIr13fwTcb5N4a0XR-pSeMDc7WiuLfRJooc";
          };
          pwned_verify = {
            name = "";
            type = "TXT";
            data = "have-i-been-pwned-verification=49efa9d605cbd57ca56c54528ea26eb3";
          };
        };
      in
      lib.pipe shared_records [
        (lib.mapAttrs (
          n: v:
          lib.recursiveUpdate {
            dns_zone = "lillecarl.com";
            ttl = 60;
          } v
        ))
      ];
  };
}
