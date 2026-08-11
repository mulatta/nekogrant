{
  lib,
  module,
  pkgs,
}:

let
  evaluate =
    configuration:
    lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      modules = [
        module
        {
          system.stateVersion = "25.11";
          services.neko = {
            enable = true;
            authentication.provider = "noauth";
            imageFile = null;
            persistence.enable = false;
          }
          // configuration;
        }
      ];
    };

  containerOf =
    configuration: (evaluate configuration).config.virtualisation.oci-containers.containers.neko;
  failedAssertionsOf =
    configuration:
    lib.filter (assertion: !assertion.assertion) (evaluate configuration).config.assertions;

  defaultContainer = containerOf { };
  hardwareAccelerationContainer = containerOf {
    hardwareAcceleration.enable = true;
  };
  rangeTcpContainer = containerOf {
    webrtc.tcpMuxPort = 59000;
  };
  muxContainer = containerOf {
    settings.desktop.screen = "1920x1080@30";
    webrtc = {
      bindAddress = "fd89:6167:656e:7473::1";
      advertisedAddresses = [ "fd89:6167:656e:7473::1" ];
      udpPortRange = null;
      udpMuxPort = 59000;
      tcpMuxPort = 59000;
    };
  };
  fileConfiguration = {
    authentication = {
      provider = "file";
      memberFile = "/run/neko-members.json";
      memberFileUnits = [ "neko-members.service" ];
    };
  };
  fileEvaluation = evaluate fileConfiguration;
  fileContainer = fileEvaluation.config.virtualisation.oci-containers.containers.neko;
  fileService = fileEvaluation.config.systemd.services.${fileContainer.serviceName};
  customRuntimeEvaluation = evaluate {
    authentication = {
      provider = "file";
      memberFile = "/run/neko-members.json";
    };
    persistence.enable = true;
    runtime = {
      uid = 1234;
      gid = 2345;
    };
  };
  customRuntimeContainer =
    customRuntimeEvaluation.config.virtualisation.oci-containers.containers.neko;
  customRuntimeService =
    customRuntimeEvaluation.config.systemd.services.${customRuntimeContainer.serviceName};
  customRuntimePrepare = builtins.head customRuntimeService.serviceConfig.ExecStartPre;

  defaultConfigFile = lib.removeSuffix ":/etc/neko/neko.yaml:ro" (
    builtins.head defaultContainer.volumes
  );
  muxConfigFile = lib.removeSuffix ":/etc/neko/neko.yaml:ro" (builtins.head muxContainer.volumes);
  fileConfigFile = lib.removeSuffix ":/etc/neko/neko.yaml:ro" (builtins.head fileContainer.volumes);

  zeroPortEvaluation = builtins.tryEval (
    builtins.deepSeq (containerOf {
      webrtc = {
        udpPortRange = null;
        udpMuxPort = 0;
      };
    }) true
  );
  unsafeExtraOptionsEvaluation = builtins.tryEval (
    builtins.deepSeq (containerOf { extraOptions = [ "--privileged" ]; }) true
  );
  removedEscapeHatchEvaluations =
    map (configuration: builtins.tryEval (builtins.deepSeq (containerOf configuration) true))
      [
        { environment.NEKO_MEMBER_OBJECT_USERS = "store-secret"; }
        { extraVolumes = [ "/tmp:/mnt" ]; }
        { devices = [ "/dev/kvm:/dev/kvm" ]; }
      ];
  zeroShmEvaluation = builtins.tryEval (builtins.deepSeq (containerOf { shmSize = "0"; }) true);
  validImageEvaluations =
    map
      (
        image:
        builtins.tryEval (
          builtins.deepSeq (containerOf {
            inherit image;
            imageFile = null;
          }) true
        )
      )
      [
        "docker.io/m1k1o/neko:3.1.5"
        "localhost:5000/m1k1o/neko:test_tag.1-2"
        "[2001:db8::1]:5000/m1k1o/neko:latest"
        "ghcr.io/m1k1o/neko@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      ];
  invalidImageEvaluations =
    map (image: builtins.tryEval (builtins.deepSeq (containerOf { inherit image; }) true))
      [
        " "
        "a"
        "a:"
        "a@@b"
        "a//b:latest"
        "a/../b:latest"
        "a@sha256:nothex"
        "a:b:c"
        "localhost:999999/repository:latest"
        "[]:5000/repository:latest"
        "UPPERCASE/repository:latest"
      ];
  validRetrievalUrlEvaluations =
    map
      (
        ipRetrievalUrl:
        builtins.tryEval (builtins.deepSeq (containerOf { webrtc = { inherit ipRetrievalUrl; }; }) true)
      )
      [
        "https://api.ipify.org"
        "http://example.invalid:8080/ip"
        "http://127.0.0.1:8080/ip"
        "http://[2001:db8::1]:8080/ip"
      ];
  invalidRetrievalUrlEvaluations =
    map
      (
        ipRetrievalUrl:
        builtins.tryEval (builtins.deepSeq (containerOf { webrtc = { inherit ipRetrievalUrl; }; }) true)
      )
      [
        "http:// "
        "http://?"
        "http:///"
        "http://example.invalid:0/ip"
        "http://example.invalid:65536/ip"
        "http://example.invalid:999999999999999999999999/ip"
        "https://user:password@example.invalid/ip"
        "https://example.invalid/ip?token=secret"
        "https://example.invalid/ip#fragment"
      ];
  invalidSettingsEvaluation = builtins.tryEval (
    builtins.deepSeq (containerOf { settings = [ ]; }) true
  );

  mismatchImageAssertions = failedAssertionsOf {
    image = "example.invalid/neko:wrong";
    imageFile = pkgs.callPackage ../packages/neko-image { };
  };
  missingProviderAssertions = failedAssertionsOf {
    authentication.provider = lib.mkForce null;
  };
  missingMemberFileAssertions = failedAssertionsOf {
    authentication = {
      provider = "file";
      memberFile = null;
    };
  };
  stagingMemberFileAssertions = failedAssertionsOf {
    authentication = {
      provider = "file";
      memberFile = "/run/neko/source-members.json";
    };
  };
  noauthMemberOptionsAssertions = failedAssertionsOf {
    authentication = {
      provider = "noauth";
      memberFile = "/run/neko-members.json";
      memberFileUnits = [ "neko-members.service" ];
    };
  };
  missingTransportAssertions = failedAssertionsOf {
    webrtc = {
      udpPortRange = null;
      udpMuxPort = null;
      tcpMuxPort = null;
    };
  };
  conflictingUdpAssertions = failedAssertionsOf {
    webrtc.udpMuxPort = 59000;
  };
  reversedRangeAssertions = failedAssertionsOf {
    webrtc.udpPortRange = {
      from = 56100;
      to = 56000;
    };
  };
  invalidAddressAssertions = failedAssertionsOf {
    listenAddress = "localhost";
  };
  cidrAddressAssertions = failedAssertionsOf {
    listenAddress = "::/64";
  };
  wildcardAdvertisedAssertions = failedAssertionsOf {
    webrtc.advertisedAddresses = [ "0.0.0.0" ];
  };
  canonicalCollisionAssertions = failedAssertionsOf {
    listenAddress = "[::1]";
    port = 59000;
    webrtc = {
      bindAddress = "0:0:0:0:0:0:0:1";
      tcpMuxPort = 59000;
    };
  };
  wildcardCollisionAssertions = failedAssertionsOf {
    listenAddress = "0.0.0.0";
    port = 59000;
    webrtc = {
      bindAddress = "127.0.0.1";
      tcpMuxPort = 59000;
    };
  };
  managedSettingAssertions = failedAssertionsOf {
    settings.server.bind = "127.0.0.1:9999";
  };
  legacyBindSettingAssertions = failedAssertionsOf {
    settings.bind = "127.0.0.1:9999";
  };
  legacyPasswordSettingAssertions = failedAssertionsOf {
    settings.password_admin = "store-secret";
  };
  caseVariantSettingAssertions = failedAssertionsOf {
    settings.member.Provider = "noauth";
  };
  parentCaseSettingAssertions = failedAssertionsOf {
    settings.Webrtc.icelite = true;
  };
  dottedSettingAssertions = failedAssertionsOf {
    settings."member.Provider" = "noauth";
  };
  secretSettingAssertions = failedAssertionsOf {
    settings.session.api_token = "store-secret";
  };
  nestedSecretSettingAssertions = failedAssertionsOf {
    settings.session.api_token.value = "store-secret";
  };
  broadcastSecretSettingAssertions = failedAssertionsOf {
    settings.capture.broadcast.url = "rtmps://broadcast.example/live/store-secret";
  };
  iceSecretSettingAssertions = failedAssertionsOf {
    settings.webrtc.iceservers.frontend = [
      {
        urls = [ "turn:turn.example" ];
        username = "store-user";
        credential = "store-secret";
      }
    ];
  };
  objectUsersSecretSettingAssertions = failedAssertionsOf {
    settings.member.object.users = [
      {
        username = "user";
        password = "store-secret";
      }
    ];
  };
  storeMemberFileAssertions = failedAssertionsOf {
    authentication = {
      provider = "file";
      memberFile = toString (pkgs.writeText "members-in-store.json" "{}");
    };
  };
  storeRootMemberFileAssertions = failedAssertionsOf {
    authentication = {
      provider = "file";
      memberFile = "/nix/store";
    };
  };
  criticalDataDirAssertions = failedAssertionsOf {
    persistence = {
      enable = true;
      dataDir = "/etc";
    };
  };
  foreignDataDirAssertions = failedAssertionsOf {
    persistence = {
      enable = true;
      dataDir = "/var/lib/systemd";
    };
  };
  whitespaceDataDirAssertions = failedAssertionsOf {
    persistence = {
      enable = true;
      dataDir = "/var/lib/neko profile";
    };
  };
  specifierDataDirAssertions = failedAssertionsOf {
    persistence = {
      enable = true;
      dataDir = "/%t";
    };
  };
  escapedDataDirAssertions = failedAssertionsOf {
    persistence = {
      enable = true;
      dataDir = "/tmp\\x2f..\\x2fetc";
    };
  };
in
assert !zeroPortEvaluation.success;
assert !unsafeExtraOptionsEvaluation.success;
assert lib.all (evaluation: !evaluation.success) removedEscapeHatchEvaluations;
assert !zeroShmEvaluation.success;
assert lib.all (evaluation: evaluation.success) validImageEvaluations;
assert lib.all (evaluation: !evaluation.success) invalidImageEvaluations;
assert lib.all (evaluation: evaluation.success) validRetrievalUrlEvaluations;
assert lib.all (evaluation: !evaluation.success) invalidRetrievalUrlEvaluations;
assert !invalidSettingsEvaluation.success;
assert lib.any (
  assertion: lib.hasInfix "must match the name and tag" assertion.message
) mismatchImageAssertions;
assert
  defaultContainer.ports == [
    "127.0.0.1:8080:8080/tcp"
    "127.0.0.1:56000-56100:56000-56100/udp"
  ];
assert
  rangeTcpContainer.ports == [
    "127.0.0.1:8080:8080/tcp"
    "127.0.0.1:56000-56100:56000-56100/udp"
    "127.0.0.1:59000:59000/tcp"
  ];
assert
  muxContainer.ports == [
    "127.0.0.1:8080:8080/tcp"
    "[fd89:6167:656e:7473:0:0:0:1]:59000:59000/udp"
    "[fd89:6167:656e:7473:0:0:0:1]:59000:59000/tcp"
  ];
assert defaultContainer.devices == [ ];
assert hardwareAccelerationContainer.devices == [ "/dev/dri:/dev/dri" ];
assert !(fileEvaluation.options.services.neko ? environment);
assert !(fileEvaluation.options.services.neko ? extraVolumes);
assert !(fileEvaluation.options.services.neko ? devices);
assert fileEvaluation.options.services.neko.hardwareAcceleration ? enable;
assert lib.elem "/run/neko/member-file.json:/run/secrets/neko-members.json:ro"
  fileContainer.volumes;
assert !(fileEvaluation.options.services.neko.authentication ? containerMemberFile);
assert lib.elem "neko-members.service" fileService.after;
assert lib.elem "neko-members.service" fileService.requires;
assert fileService.startLimitIntervalSec == 300;
assert fileService.startLimitBurst == 3;
assert fileService.serviceConfig.RuntimeDirectory == "neko";
assert fileService.serviceConfig.RuntimeDirectoryMode == "0700";
assert fileService.serviceConfig.RestartSec == "30s";
assert lib.hasInfix "neko-member-file-prepare" (
  builtins.head fileService.serviceConfig.ExecStartPre
);
assert lib.elem "d /var/lib/neko/chromium 0750 1234 2345 - -"
  customRuntimeEvaluation.config.systemd.tmpfiles.rules;
assert defaultContainer.environment.NEKO_CONFIG == "/etc/neko/neko.yaml";
assert defaultContainer.environment.NEKO_MEMBER_PROVIDER == "noauth";
assert defaultContainer.environment.NEKO_SERVER_BIND == "0.0.0.0:8080";
assert defaultContainer.environment.USER == "neko";
assert lib.any (
  assertion: lib.hasInfix "must be selected" assertion.message
) missingProviderAssertions;
assert lib.any (
  assertion: lib.hasInfix "requires an absolute memberFile" assertion.message
) missingMemberFileAssertions;
assert lib.any (
  assertion: lib.hasInfix "module-managed /run/neko" assertion.message
) stagingMemberFileAssertions;
assert lib.any (assertion: lib.hasInfix "may only" assertion.message) noauthMemberOptionsAssertions;
assert lib.any (
  assertion: lib.hasInfix "must configure" assertion.message
) missingTransportAssertions;
assert lib.any (
  assertion: lib.hasInfix "cannot be combined" assertion.message
) conflictingUdpAssertions;
assert lib.any (
  assertion: lib.hasInfix "must not be greater" assertion.message
) reversedRangeAssertions;
assert lib.any (
  assertion: lib.hasInfix "literal IPv4 or IPv6" assertion.message
) invalidAddressAssertions;
assert lib.any (
  assertion: lib.hasInfix "literal IPv4 or IPv6" assertion.message
) cidrAddressAssertions;
assert lib.any (
  assertion: lib.hasInfix "cannot contain unspecified" assertion.message
) wildcardAdvertisedAssertions;
assert lib.any (
  assertion: lib.hasInfix "overlapping addresses" assertion.message
) canonicalCollisionAssertions;
assert lib.any (
  assertion: lib.hasInfix "overlapping addresses" assertion.message
) wildcardCollisionAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.server.bind is managed" assertion.message
) managedSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.bind is managed" assertion.message
) legacyBindSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.password_admin is managed" assertion.message
) legacyPasswordSettingAssertions;
assert lib.any (assertion: lib.hasInfix "lowercase" assertion.message) caseVariantSettingAssertions;
assert lib.any (assertion: lib.hasInfix "lowercase" assertion.message) parentCaseSettingAssertions;
assert lib.any (assertion: lib.hasInfix "lowercase" assertion.message) dottedSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.session.api_token is managed" assertion.message
) secretSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.session.api_token is managed" assertion.message
) nestedSecretSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.capture.broadcast.url is managed" assertion.message
) broadcastSecretSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.webrtc.iceservers.frontend is managed" assertion.message
) iceSecretSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "settings.member.object.users is managed" assertion.message
) objectUsersSecretSettingAssertions;
assert lib.any (
  assertion: lib.hasInfix "outside /nix/store" assertion.message
) storeMemberFileAssertions;
assert lib.any (
  assertion: lib.hasInfix "outside /nix/store" assertion.message
) storeRootMemberFileAssertions;
assert lib.any (
  assertion: lib.hasInfix "must be /var/lib/neko" assertion.message
) criticalDataDirAssertions;
assert lib.any (
  assertion: lib.hasInfix "must be /var/lib/neko" assertion.message
) foreignDataDirAssertions;
assert lib.any (
  assertion: lib.hasInfix "must be /var/lib/neko" assertion.message
) whitespaceDataDirAssertions;
assert lib.any (
  assertion: lib.hasInfix "must be /var/lib/neko" assertion.message
) specifierDataDirAssertions;
assert lib.any (
  assertion: lib.hasInfix "must be /var/lib/neko" assertion.message
) escapedDataDirAssertions;
pkgs.runCommand "neko-module-evaluation" { } ''
  grep -q 'bind: 0.0.0.0:8080' ${defaultConfigFile}
  grep -q 'epr: 56000-56100' ${defaultConfigFile}
  grep -q 'legacy: false' ${defaultConfigFile}
  grep -q 'provider: noauth' ${defaultConfigFile}
  grep -q 'enabled: false' ${defaultConfigFile}
  grep -q 'implicit_hosting: false' ${defaultConfigFile}
  grep -q 'screen: 1920x1080@30' ${muxConfigFile}
  grep -q 'tcpmux: 59000' ${muxConfigFile}
  grep -q 'udpmux: 59000' ${muxConfigFile}
  grep -q 'provider: file' ${fileConfigFile}
  grep -q 'path: /run/secrets/neko-members.json' ${fileConfigFile}
  grep -q -- '--owner=1234 --group=2345' ${customRuntimePrepare}
  touch "$out"
''
