{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.postfix;
  user = cfg.user;
  group = cfg.group;
  setgidGroup = cfg.setgidGroup;

  mainCf =
    ''
      queue_directory = /var/postfix/queue
      command_directory = ${pkgs.postfix}/sbin
      daemon_directory = ${pkgs.postfix}/libexec/postfix

      mail_owner = ${user}
      default_privs = nobody

    ''
    + optionalString config.networking.enableIPv6 ''
      inet_protocols = all
    ''
    + (if cfg.networks != null then
        ''
          mynetworks = ${concatStringsSep ", " cfg.networks}
        ''
      else if cfg.networksStyle != "" then
        ''
          mynetworks_style = ${cfg.networksStyle}
        ''
      else
        # Postfix default is subnet, but let's play safe
        ''
          mynetworks_style = host
        '')
    + optionalString (cfg.hostname != "") ''
      myhostname = ${cfg.hostname}
    ''
    + optionalString (cfg.domain != "") ''
      mydomain = ${cfg.domain}
    ''
    + optionalString (cfg.origin != "") ''
      myorigin = ${cfg.origin}
    ''
    + optionalString (cfg.destination != null) ''
      mydestination = ${concatStringsSep ", " cfg.destination}
    ''
    + optionalString (cfg.relayDomains != null) ''
      relay_domains = ${concatStringsSep ", " cfg.relayDomains}
    ''
    + ''
      local_recipient_maps =

      relayhost = ${if cfg.lookupMX || cfg.relayHost == "" then
          cfg.relayHost
        else
          "[" + cfg.relayHost + "]"}

      alias_maps = hash:/var/postfix/conf/aliases

      mail_spool_directory = /var/spool/mail/

      setgid_group = ${setgidGroup}
    ''
    + optionalString (cfg.sslCert != "") ''

      smtp_tls_CAfile = ${cfg.sslCACert}
      smtp_tls_cert_file = ${cfg.sslCert}
      smtp_tls_key_file = ${cfg.sslKey}

      smtp_use_tls = yes

      smtpd_tls_CAfile = ${cfg.sslCACert}
      smtpd_tls_cert_file = ${cfg.sslCert}
      smtpd_tls_key_file = ${cfg.sslKey}

      smtpd_use_tls = yes

      recipientDelimiter = ${cfg.recipientDelimiter}
    ''
    + cfg.extraConfig;

  aliases =
    optionalString (cfg.postmasterAlias != "") ''
      postmaster: ${cfg.postmasterAlias}
    ''
    + optionalString (cfg.rootAlias != "") ''
      root: ${cfg.rootAlias}
    ''
    + cfg.extraAliases
  ;

  aliasesFile = pkgs.writeText "postfix-aliases" aliases;
  mainCfFile = pkgs.writeText "postfix-main.cf" mainCf;

in

{

  ###### interface

  options = {

    services.postfix = {

      enable = mkOption {
        default = false;
        description = "Whether to run the Postfix mail server.";
      };

      setSendmail = mkOption {
        default = true;
        description = "Whether to set the system sendmail to postfix's.";
      };

      user = mkOption {
        default = "postfix";
        description = "What to call the Postfix user (must be used only for postfix).";
      };

      group = mkOption {
        default = "postfix";
        description = "What to call the Postfix group (must be used only for postfix).";
      };

      setgidGroup = mkOption {
        default = "postdrop";
        description = "
          How to call postfix setgid group (for postdrop). Should
          be uniquely used group.
        ";
      };

      networks = mkOption {
        default = null;
        example = ["192.168.0.1/24"];
        description = "
          Net masks for trusted - allowed to relay mail to third parties -
          hosts. Leave empty to use mynetworks_style configuration or use
          default (localhost-only).
        ";
      };

      networksStyle = mkOption {
        default = "";
        description = "
          Name of standard way of trusted network specification to use,
          leave blank if you specify it explicitly or if you want to use
          default (localhost-only).
        ";
      };

      hostname = mkOption {
        default = "";
        description ="
          Hostname to use. Leave blank to use just the hostname of machine.
          It should be FQDN.
        ";
      };

      domain = mkOption {
        default = "";
        description ="
          Domain to use. Leave blank to use hostname minus first component.
        ";
      };

      origin = mkOption {
        default = "";
        description ="
          Origin to use in outgoing e-mail. Leave blank to use hostname.
        ";
      };

      destination = mkOption {
        default = null;
        example = ["localhost"];
        description = "
          Full (!) list of domains we deliver locally. Leave blank for
          acceptable Postfix default.
        ";
      };

      relayDomains = mkOption {
        default = null;
        example = ["localdomain"];
        description = "
          List of domains we agree to relay to. Default is the same as
          destination.
        ";
      };

      relayHost = mkOption {
        default = "";
        description = "
          Mail relay for outbound mail.
        ";
      };

      lookupMX = mkOption {
        default = false;
        description = "
          Whether relay specified is just domain whose MX must be used.
        ";
      };

      postmasterAlias = mkOption {
        default = "root";
        description = "Who should receive postmaster e-mail.";
      };

      rootAlias = mkOption {
        default = "";
        description = "
          Who should receive root e-mail. Blank for no redirection.
        ";
      };

      extraAliases = mkOption {
        default = "";
        description = "
          Additional entries to put verbatim into aliases file.
        ";
      };

      extraConfig = mkOption {
        default = "";
        description = "
          Extra configuration, will be added verbatim to the configuration file.
        ";
      };

      sslCert = mkOption {
        default = "";
        description = "SSL certificate to use.";
      };

      sslCACert = mkOption {
        default = "";
        description = "SSL certificate of CA.";
      };

      sslKey = mkOption {
        default = "";
        description = "SSL key to use.";
      };

      recipientDelimiter = mkOption {
        default = "";
        example = "+";
        description = "
          Delimiter for address extension: so mail to user+test can be handled by ~user/.forward+test
        ";
      };

    };

  };


  ###### implementation

  config = mkIf config.services.postfix.enable {

    environment = {
      etc = singleton
        { source = "/var/postfix/conf";
          target = "postfix";
        };

      # This makes comfortable for root to run 'postqueue' for example.
      systemPackages = [ pkgs.postfix ];
    };

    services.mail.sendmailSetuidWrapper = mkIf config.services.postfix.setSendmail {
      program = "sendmail";
      source = "${pkgs.postfix}/bin/sendmail";
      owner = "nobody";
      group = "postdrop";
      setuid = false;
      setgid = true;
    };

    users.extraUsers = singleton
      { name = user;
        description = "Postfix mail server user";
        uid = config.ids.uids.postfix;
        group = group;
      };

    users.extraGroups =
      [ { name = group;
          gid = config.ids.gids.postfix;
        }
        { name = setgidGroup;
          gid = config.ids.gids.postdrop;
        }
      ];

    jobs.postfix =
      # I copy _lots_ of shipped configuration filed
      # that can be left as is. I am afraid the exact
      # will list slightly change in next Postfix
      # release, so listing them all one-by-one in an
      # accurate way is unlikely to be better.
      { description = "Postfix mail server";

        startOn = "started networking";

        daemonType = "none";

        respawn = true;

        environment.TZ = config.time.timeZone;

        script = ''
          while ${pkgs.procps}/bin/ps `${pkgs.coreutils}/bin/cat /var/postfix/queue/pid/master.pid` |
            grep -q postfix
          do
            ${pkgs.coreutils}/bin/sleep 1m
          done
        '';

        preStart =
          ''
            if ! [ -d /var/spool/postfix ]; then
              ${pkgs.coreutils}/bin/mkdir -p /var/spool/mail /var/postfix/conf /var/postfix/queue
            fi

            ${pkgs.coreutils}/bin/chown -R ${user}:${group} /var/postfix
            ${pkgs.coreutils}/bin/chown -R ${user}:${setgidGroup} /var/postfix/queue
            ${pkgs.coreutils}/bin/chmod -R ug+rwX /var/postfix/queue
            ${pkgs.coreutils}/bin/chown root:root /var/spool/mail
            ${pkgs.coreutils}/bin/chmod a+rwxt /var/spool/mail

            ln -sf ${pkgs.postfix}/share/postfix/conf/* /var/postfix/conf

            ln -sf ${aliasesFile} /var/postfix/conf/aliases
            ln -sf ${mainCfFile} /var/postfix/conf/main.cf

            ${pkgs.postfix}/sbin/postalias -c /var/postfix/conf /var/postfix/conf/aliases

            exec ${pkgs.postfix}/sbin/postfix -c /var/postfix/conf start
          ''; # */

        preStop = ''
            exec ${pkgs.postfix}/sbin/postfix -c /var/postfix/conf stop
        '';

      };

  };

}
