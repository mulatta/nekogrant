{
  module,
  pkgs,
}:

let
  testMemberFile = pkgs.writeText "neko-test-members.json" (
    builtins.toJSON {
      operator = {
        password = "xjiDP2m7+zwmevoKdENIEkNrjwioH9Jjxr5ocd5PEmU=";
        profile = {
          name = "Operator";
          is_admin = true;
          can_login = true;
          can_connect = true;
          can_watch = true;
          can_host = true;
          can_share_media = false;
          can_access_clipboard = true;
          sends_inactive_cursor = false;
          can_see_inactive_cursors = false;
          plugins = { };
        };
      };
    }
  );
in
pkgs.testers.runNixOSTest {
  name = "neko";

  nodes.machine = {
    imports = [ module ];

    services.neko = {
      enable = true;
      authentication = {
        provider = "file";
        memberFile = "/run/neko-test/members.json";
        memberFileUnits = [ "neko-test-member-file.service" ];
      };
      persistence.enable = false;
      webrtc = {
        advertisedAddresses = [ "127.0.0.1" ];
        udpPortRange = null;
        udpMuxPort = 59000;
        tcpMuxPort = 59000;
      };
      settings.desktop.screen = "1024x768@30";
    };

    systemd.services.neko-test-member-file = {
      description = "Create a root-only Neko member-file fixture";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.coreutils}/bin/install -D -m 0400 -o root -g root \
          ${testMemberFile} /run/neko-test/members.json
      '';
    };

    virtualisation = {
      cores = 2;
      diskSize = 8192;
      memorySize = 3072;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("neko-test-member-file.service")
    machine.succeed("test $(stat -c %U:%G:%a /run/neko-test/members.json) = root:root:400")
    machine.wait_for_unit("podman-neko.service", timeout=300)
    machine.wait_for_open_port(8080, timeout=300)
    machine.succeed("curl --fail --silent http://127.0.0.1:8080/health")
    machine.succeed("podman exec --user 1000 neko test -r /run/secrets/neko-members.json")
    machine.succeed("test $(stat -c %U:%G:%a /run/neko) = root:root:700")
    machine.succeed("test $(stat -c %u:%g:%a /run/neko/member-file.json) = 1000:1000:400")
    machine.succeed("podman exec neko grep -q 'screen: 1024x768@30' /etc/neko/neko.yaml")
    machine.succeed("podman exec neko grep -q 'provider: file' /etc/neko/neko.yaml")
    machine.succeed("podman exec neko grep -q 'path: /run/secrets/neko-members.json' /etc/neko/neko.yaml")
    machine.succeed(
      "curl --fail --silent --header 'Content-Type: application/json' "
      + "--data '{\"username\":\"operator\",\"password\":\"test-password\"}' "
      + "http://127.0.0.1:8080/api/login | grep -q '\"name\":\"Operator\"'"
    )

    machine.succeed("systemctl stop podman-neko.service")
    machine.succeed("rm /run/neko-test/members.json")
    machine.fail("systemctl start podman-neko.service")
    machine.succeed("systemctl stop podman-neko.service")
    machine.succeed("test ! -e /run/neko/member-file.json")
    machine.succeed(
      "journalctl -u podman-neko.service --no-pager | "
      + "grep -q 'member file is missing or is not a regular file'"
    )
  '';
}
