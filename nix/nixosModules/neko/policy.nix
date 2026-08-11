{ lib }:

let
  canonicalSettingLeafPaths =
    settings:
    let
      walk =
        prefix: value:
        if builtins.isAttrs value && !lib.isDerivation value then
          lib.concatMap (
            name:
            let
              child = value.${name};
              path = prefix ++ map lib.toLower (lib.splitString "." name);
            in
            if builtins.isAttrs child && child != { } then walk path child else [ path ]
          ) (lib.attrNames value)
        else
          [ prefix ];
    in
    walk [ ] settings;

  settingsKeysAreCanonical =
    settings:
    let
      walk =
        value:
        lib.isDerivation value
        || !builtins.isAttrs value
        || lib.all (name: name == lib.toLower name && !(lib.hasInfix "." name) && walk value.${name}) (
          lib.attrNames value
        );
    in
    walk settings;

  reservedSettingPaths = [
    {
      path = [ "bind" ];
      option = "services.neko.listenAddress/port";
    }
    {
      path = [ "broadcast_url" ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [ "epr" ];
      option = "services.neko.webrtc.udpPortRange";
    }
    {
      path = [ "iceserver" ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [ "iceservers" ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [ "implicit_control" ];
      option = "services.neko.session.implicitHosting";
    }
    {
      path = [ "ipfetch" ];
      option = "services.neko.webrtc.ipRetrievalUrl";
    }
    {
      path = [ "nat1to1" ];
      option = "services.neko.webrtc.advertisedAddresses";
    }
    {
      path = [ "password" ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [ "password_admin" ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [ "tcpmux" ];
      option = "services.neko.webrtc.tcpMuxPort";
    }
    {
      path = [ "udpmux" ];
      option = "services.neko.webrtc.udpMuxPort";
    }
    {
      path = [
        "capture"
        "broadcast"
        "url"
      ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [ "legacy" ];
      option = "services.neko.legacy.enable";
    }
    {
      path = [
        "server"
        "bind"
      ];
      option = "services.neko.listenAddress/port";
    }
    {
      path = [
        "plugins"
        "enabled"
      ];
      option = "services.neko.plugins.enable";
    }
    {
      path = [
        "session"
        "implicit_hosting"
      ];
      option = "services.neko.session.implicitHosting";
    }
    {
      path = [
        "session"
        "api_token"
      ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [
        "member"
        "provider"
      ];
      option = "services.neko.authentication.provider";
    }
    {
      path = [
        "member"
        "file"
        "path"
      ];
      option = "services.neko.authentication.memberFile";
    }
    {
      path = [
        "member"
        "file"
        "hash"
      ];
      option = "services.neko.authentication.memberFile";
    }
    {
      path = [
        "member"
        "multiuser"
        "user_password"
      ];
      option = "runtime credentials outside services.neko.settings";
    }
    {
      path = [
        "member"
        "multiuser"
        "admin_password"
      ];
      option = "runtime credentials outside services.neko.settings";
    }
    {
      path = [
        "member"
        "object"
        "users"
      ];
      option = "runtime credentials outside services.neko.settings";
    }
    {
      path = [
        "webrtc"
        "iceservers"
        "frontend"
      ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [
        "webrtc"
        "iceservers"
        "backend"
      ];
      option = "a runtime credential outside services.neko.settings";
    }
    {
      path = [
        "webrtc"
        "epr"
      ];
      option = "services.neko.webrtc.udpPortRange";
    }
    {
      path = [
        "webrtc"
        "udpmux"
      ];
      option = "services.neko.webrtc.udpMuxPort";
    }
    {
      path = [
        "webrtc"
        "tcpmux"
      ];
      option = "services.neko.webrtc.tcpMuxPort";
    }
    {
      path = [
        "webrtc"
        "nat1to1"
      ];
      option = "services.neko.webrtc.advertisedAddresses";
    }
    {
      path = [
        "webrtc"
        "ip_retrieval_url"
      ];
      option = "services.neko.webrtc.ipRetrievalUrl";
    }
  ];
in
{
  inherit
    canonicalSettingLeafPaths
    reservedSettingPaths
    settingsKeysAreCanonical
    ;
}
