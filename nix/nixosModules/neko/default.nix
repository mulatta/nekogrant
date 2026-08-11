{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.neko;
  yaml = pkgs.formats.yaml { };
  validation = import ./validation.nix { inherit lib; };
  policy = import ./policy.nix { inherit lib; };

  inherit (validation)
    addressIsValid
    addressesOverlap
    absolutePathIsLexicallyClean
    formatBindAddress
    imageReferenceIsValid
    ipv6AnyAddress
    normalizeAddress
    retrievalUrlIsValid
    ;

  defaultImageFile = pkgs.callPackage ../../packages/neko-image { };
  defaultImage = "${defaultImageFile.imageName}:${defaultImageFile.imageTag}";
  imageFileReference =
    if cfg.imageFile != null && cfg.imageFile ? imageName && cfg.imageFile ? imageTag then
      "${cfg.imageFile.imageName}:${cfg.imageFile.imageTag}"
    else
      null;
  networkPortType = lib.types.ints.between 1 65535;

  listenAddress = normalizeAddress cfg.listenAddress;
  webRtcBindAddress = normalizeAddress cfg.webrtc.bindAddress;
  advertisedAddresses = lib.unique (map normalizeAddress cfg.webrtc.advertisedAddresses);

  webRtcSettings =
    lib.optionalAttrs (cfg.webrtc.udpPortRange != null) {
      epr = "${toString cfg.webrtc.udpPortRange.from}-${toString cfg.webrtc.udpPortRange.to}";
    }
    // lib.optionalAttrs (cfg.webrtc.udpMuxPort != null) {
      udpmux = cfg.webrtc.udpMuxPort;
    }
    // lib.optionalAttrs (cfg.webrtc.tcpMuxPort != null) {
      tcpmux = cfg.webrtc.tcpMuxPort;
    }
    // {
      nat1to1 = advertisedAddresses;
      ip_retrieval_url = if cfg.webrtc.ipRetrievalUrl == null then "" else cfg.webrtc.ipRetrievalUrl;
    };

  authenticationSettings = lib.optionalAttrs (cfg.authentication.provider != null) {
    member = {
      provider = cfg.authentication.provider;
    }
    // lib.optionalAttrs (cfg.authentication.provider == "file") {
      file = {
        path = containerMemberFile;
        hash = true;
      };
    };
  };

  managedSettings = {
    legacy = cfg.legacy.enable;
    server.bind = "0.0.0.0:8080";
    plugins.enabled = cfg.plugins.enable;
    session.implicit_hosting = cfg.session.implicitHosting;
    webrtc = webRtcSettings;
  }
  // authenticationSettings;

  effectiveSettings = lib.recursiveUpdate cfg.settings managedSettings;
  configFile = yaml.generate "neko.yaml" effectiveSettings;

  managedEnvironment = {
    NEKO_CONFIG = "/etc/neko/neko.yaml";
    NEKO_PLUGINS_ENABLED = lib.boolToString cfg.plugins.enable;
    NEKO_SERVER_BIND = "0.0.0.0:8080";
    USER = "neko";
  }
  // lib.optionalAttrs (cfg.authentication.provider != null) {
    NEKO_MEMBER_PROVIDER = cfg.authentication.provider;
  }
  // lib.optionalAttrs (cfg.authentication.provider == "file") {
    NEKO_MEMBER_FILE_HASH = "true";
    NEKO_MEMBER_FILE_PATH = containerMemberFile;
  };
  httpPort = "${formatBindAddress listenAddress}:${toString cfg.port}:8080/tcp";
  webRtcPorts =
    lib.optional (cfg.webrtc.udpPortRange != null) (
      "${formatBindAddress webRtcBindAddress}:${toString cfg.webrtc.udpPortRange.from}-${toString cfg.webrtc.udpPortRange.to}:"
      + "${toString cfg.webrtc.udpPortRange.from}-${toString cfg.webrtc.udpPortRange.to}/udp"
    )
    ++
      lib.optional (cfg.webrtc.udpMuxPort != null)
        "${formatBindAddress webRtcBindAddress}:${toString cfg.webrtc.udpMuxPort}:${toString cfg.webrtc.udpMuxPort}/udp"
    ++
      lib.optional (cfg.webrtc.tcpMuxPort != null)
        "${formatBindAddress webRtcBindAddress}:${toString cfg.webrtc.tcpMuxPort}:${toString cfg.webrtc.tcpMuxPort}/tcp";

  profileDir = "${cfg.persistence.dataDir}/chromium";
  containerServiceName = config.virtualisation.oci-containers.containers.neko.serviceName;
  containerMemberFile = "/run/secrets/neko-members.json";
  stagedMemberFile = "/run/neko/member-file.json";
  memberFile =
    if cfg.authentication.memberFile == null then
      "/run/neko-member-file-not-configured"
    else
      cfg.authentication.memberFile;
  memberFilePrepare = pkgs.writeShellApplication {
    name = "neko-member-file-prepare";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      source=${lib.escapeShellArg memberFile}
      destination=${lib.escapeShellArg stagedMemberFile}
      temporary="''${destination}.tmp"

      rm -f "$destination" "$temporary"
      if [[ ! -f "$source" ]]; then
        echo "Neko member file is missing or is not a regular file: $source" >&2
        exit 1
      fi

      trap 'rm -f "$temporary"' EXIT
      install --mode=0400 --owner=${toString cfg.runtime.uid} --group=${toString cfg.runtime.gid} "$source" "$temporary"
      mv -f "$temporary" "$destination"
      trap - EXIT
    '';
  };
  memberFileVolume = lib.optional (
    cfg.authentication.provider == "file"
  ) "${stagedMemberFile}:${containerMemberFile}:ro";

  canonicalSettingLeafPaths = policy.canonicalSettingLeafPaths cfg.settings;
  settingsHaveCanonicalCollisions =
    lib.length canonicalSettingLeafPaths != lib.length (lib.unique canonicalSettingLeafPaths);
  settingsKeysAreCanonical = policy.settingsKeysAreCanonical cfg.settings;
  inherit (policy) reservedSettingPaths;

in
{
  options.services.neko = {
    enable = lib.mkEnableOption "Neko shared browser container";

    image = lib.mkOption {
      type = lib.types.addCheck lib.types.nonEmptyStr imageReferenceIsValid;
      default = defaultImage;
      description = ''
        Canonical OCI image reference with an explicit tag or sha256 digest.
        When imageFile is set, this must match the name and tag contained in
        that image archive.
      '';
    };

    imageFile = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = defaultImageFile;
      defaultText = lib.literalExpression "pkgs.callPackage <nekogrant/nix/packages/neko-image> { }";
      description = ''
        OCI image archive loaded before starting Neko. Set this to null to let
        the configured OCI backend pull image from its registry.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to start the Neko container automatically at boot.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "127.0.0.1";
      description = "Literal host IPv4 or IPv6 address on which Neko HTTP is published.";
    };

    port = lib.mkOption {
      type = networkPortType;
      default = 8080;
      description = "Host TCP port on which the Neko HTTP service is published.";
    };

    shmSize = lib.mkOption {
      type = lib.types.strMatching "^[1-9][0-9]*[kKmMgGtT]?$";
      default = "2g";
      description = "Shared-memory size passed to the OCI container.";
    };

    runtime = {
      uid = lib.mkOption {
        type = lib.types.ints.between 0 4294967294;
        default = 1000;
        description = ''
          Numeric UID used by the Neko process inside the image. This controls
          profile and staged member-file ownership; it does not override the
          image entrypoint user.
        '';
      };

      gid = lib.mkOption {
        type = lib.types.ints.between 0 4294967294;
        default = 1000;
        description = ''
          Numeric GID used by the Neko process inside the image. This controls
          profile and staged member-file ownership; it does not override the
          image entrypoint group.
        '';
      };
    };

    webrtc = {
      bindAddress = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "127.0.0.1";
        description = "Literal host IPv4 or IPv6 address on which WebRTC ports are published.";
      };

      advertisedAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [ "127.0.0.1" ];
        description = "Literal addresses written to Neko's webrtc.nat1to1 setting.";
      };

      ipRetrievalUrl = lib.mkOption {
        type = lib.types.nullOr (lib.types.addCheck lib.types.nonEmptyStr retrievalUrlIsValid);
        default = null;
        description = ''
          Explicit HTTP(S) endpoint used to discover a WebRTC address; null
          disables retrieval. Userinfo, query strings, fragments, whitespace,
          and invalid or out-of-range ports are rejected so credentials cannot
          be embedded in the generated Nix-store configuration.
        '';
      };

      udpPortRange = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              from = lib.mkOption {
                type = networkPortType;
                default = 56000;
                description = "First UDP port in the WebRTC ephemeral port range.";
              };
              to = lib.mkOption {
                type = networkPortType;
                default = 56100;
                description = "Last UDP port in the WebRTC ephemeral port range.";
              };
            };
          }
        );
        default = { };
        description = ''
          WebRTC UDP port range. It can be combined with a TCP mux, but not a
          UDP mux. Set it to null when using only mux transports.
        '';
      };

      udpMuxPort = lib.mkOption {
        type = lib.types.nullOr networkPortType;
        default = null;
        description = "Single UDP WebRTC multiplexing port, used instead of udpPortRange.";
      };

      tcpMuxPort = lib.mkOption {
        type = lib.types.nullOr networkPortType;
        default = null;
        description = "Optional single TCP WebRTC multiplexing port.";
      };
    };

    authentication = {
      provider = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "file"
            "noauth"
          ]
        );
        default = null;
        description = "Neko member provider; select the file provider or explicit noauth mode.";
      };

      memberFile = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        example = "/run/neko-members.json";
        description = ''
          Runtime JSON member file used by the file provider. It must exist and
          be root-readable before the container service starts, and must remain
          outside /nix/store. At each start the module copies it into a private
          /run staging directory with services.neko.runtime UID/GID ownership,
          then mounts that copy read-only at the fixed in-container path
          /run/secrets/neko-members.json.
        '';
      };

      memberFileUnits = lib.mkOption {
        type = lib.types.listOf (
          lib.types.strMatching "[A-Za-z0-9@%:_.-]+[.](service|socket|device|mount|automount|swap|target|path|timer|scope|slice)"
        );
        default = [ ];
        example = [ "sops-nix.service" ];
        description = ''
          Systemd units that produce authentication.memberFile. In file mode
          the Neko container requires and starts after these units, so secret
          material is available before the staging preflight runs.
        '';
      };
    };

    legacy.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable Neko's legacy configuration and API surface.";
    };

    plugins.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable Neko plugins.";
    };

    session.implicitHosting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether eligible members implicitly become Neko host when connecting.";
    };

    settings = lib.mkOption {
      type = lib.types.addCheck yaml.type (value: builtins.isAttrs value && !lib.isDerivation value);
      default = { };
      description = ''
        Non-secret Neko configuration written to /etc/neko/neko.yaml. Keys
        managed by dedicated options are rejected case-insensitively, including
        Viper dotted-key aliases. The generated file is world-readable.
      '';
    };

    persistence = {
      enable = lib.mkEnableOption "persistent Chromium profile data" // {
        default = true;
      };

      dataDir = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "/var/lib/neko";
        description = "Safe host directory below /var/lib under which persistent Neko data is stored.";
      };
    };

    hardwareAcceleration.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to expose /dev/dri to the Neko container. The host device must
        already exist and its permissions must allow the image runtime UID/GID
        to use it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = imageFileReference == null || cfg.image == imageFileReference;
        message = "services.neko.image must match the name and tag declared by imageFile.";
      }
      {
        assertion = addressIsValid cfg.listenAddress;
        message = "services.neko.listenAddress must be a literal IPv4 or IPv6 address.";
      }
      {
        assertion = addressIsValid cfg.webrtc.bindAddress;
        message = "services.neko.webrtc.bindAddress must be a literal IPv4 or IPv6 address.";
      }
      {
        assertion = lib.all addressIsValid cfg.webrtc.advertisedAddresses;
        message = "services.neko.webrtc.advertisedAddresses must contain literal IPv4 or IPv6 addresses.";
      }
      {
        assertion = lib.all (
          address:
          let
            normalized = normalizeAddress address;
          in
          normalized != "0.0.0.0" && normalized != ipv6AnyAddress
        ) cfg.webrtc.advertisedAddresses;
        message = "services.neko.webrtc.advertisedAddresses cannot contain unspecified wildcard addresses.";
      }
      {
        assertion = cfg.webrtc.advertisedAddresses != [ ] || cfg.webrtc.ipRetrievalUrl != null;
        message = "WebRTC requires advertisedAddresses or an explicit ipRetrievalUrl.";
      }
      {
        assertion = cfg.webrtc.udpPortRange == null || cfg.webrtc.udpMuxPort == null;
        message = "services.neko.webrtc.udpPortRange cannot be combined with a UDP mux port.";
      }
      {
        assertion =
          cfg.webrtc.udpPortRange != null || cfg.webrtc.udpMuxPort != null || cfg.webrtc.tcpMuxPort != null;
        message = "services.neko.webrtc must configure a UDP range, UDP mux, or TCP mux.";
      }
      {
        assertion =
          cfg.webrtc.udpPortRange == null || cfg.webrtc.udpPortRange.from <= cfg.webrtc.udpPortRange.to;
        message = "services.neko.webrtc.udpPortRange.from must not be greater than to.";
      }
      {
        assertion =
          cfg.webrtc.tcpMuxPort == null
          || cfg.webrtc.tcpMuxPort != cfg.port
          || !(addressesOverlap listenAddress webRtcBindAddress);
        message = "Neko HTTP and WebRTC TCP mux cannot publish overlapping addresses on the same port.";
      }
      {
        assertion = cfg.authentication.provider != null;
        message = "services.neko.authentication.provider must be selected explicitly.";
      }
      {
        assertion =
          cfg.authentication.provider != "file"
          || (
            cfg.authentication.memberFile != null
            && absolutePathIsLexicallyClean cfg.authentication.memberFile
            && cfg.authentication.memberFile != "/nix/store"
            && !lib.hasPrefix "/nix/store/" cfg.authentication.memberFile
            && cfg.authentication.memberFile != "/run/neko"
            && !lib.hasPrefix "/run/neko/" cfg.authentication.memberFile
          );
        message = ''
          The file provider requires an absolute memberFile outside /nix/store
          and the module-managed /run/neko staging directory.
        '';
      }
      {
        assertion =
          cfg.authentication.provider == "file"
          || (cfg.authentication.memberFile == null && cfg.authentication.memberFileUnits == [ ]);
        message = ''
          services.neko.authentication.memberFile and memberFileUnits may only
          be set when the file provider is selected.
        '';
      }
      {
        assertion =
          absolutePathIsLexicallyClean cfg.persistence.dataDir
          && (
            cfg.persistence.dataDir == "/var/lib/neko" || lib.hasPrefix "/var/lib/neko/" cfg.persistence.dataDir
          )
          && !(lib.hasInfix ":" cfg.persistence.dataDir)
          && !(lib.hasInfix "\n" cfg.persistence.dataDir);
        message = "services.neko.persistence.dataDir must be /var/lib/neko or a safe child path.";
      }
      {
        assertion = settingsKeysAreCanonical;
        message = "services.neko.settings keys must be lowercase and must not contain dots.";
      }
      {
        assertion = !settingsHaveCanonicalCollisions;
        message = "services.neko.settings contains keys that collide after Viper normalization.";
      }
    ]
    ++ map (entry: {
      assertion =
        !(lib.any (
          leaf: lib.lists.hasPrefix entry.path leaf || lib.lists.hasPrefix leaf entry.path
        ) canonicalSettingLeafPaths);
      message = "services.neko.settings.${lib.concatStringsSep "." entry.path} is managed by ${entry.option}.";
    }) reservedSettingPaths;

    warnings = lib.optional (cfg.authentication.provider == "noauth") ''
      Neko authentication is disabled explicitly; keep all listeners private.
    '';

    systemd.tmpfiles.rules = lib.optionals cfg.persistence.enable [
      "d ${cfg.persistence.dataDir} 0750 root root - -"
      "d ${profileDir} 0750 ${toString cfg.runtime.uid} ${toString cfg.runtime.gid} - -"
    ];

    systemd.services.${containerServiceName} = lib.mkIf (cfg.authentication.provider == "file") {
      after = cfg.authentication.memberFileUnits;
      requires = cfg.authentication.memberFileUnits;
      startLimitIntervalSec = 300;
      startLimitBurst = 3;
      serviceConfig = {
        RuntimeDirectory = "neko";
        RuntimeDirectoryMode = "0700";
        RestartSec = "30s";
        ExecStartPre = lib.mkBefore [ "${memberFilePrepare}/bin/neko-member-file-prepare" ];
      };
    };

    virtualisation.oci-containers.containers.neko = {
      inherit (cfg)
        autoStart
        image
        imageFile
        ;
      environment = managedEnvironment;
      pull = if cfg.imageFile == null then "missing" else "never";
      ports = [ httpPort ] ++ webRtcPorts;
      volumes = [
        "${configFile}:/etc/neko/neko.yaml:ro"
      ]
      ++ memberFileVolume
      ++ lib.optional cfg.persistence.enable "${profileDir}:/home/neko/.config/chromium";
      devices = lib.optional cfg.hardwareAcceleration.enable "/dev/dri:/dev/dri";
      extraOptions = [ "--shm-size=${cfg.shmSize}" ];
    };
  };
}
