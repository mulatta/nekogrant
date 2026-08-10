{
  pkgs,
  treefmt,
}:

pkgs.mkShell {
  packages =
    with pkgs;
    [
      caddy
      curl
      delve
      go
      gopls
      jq
      nil
      nix-prefetch-docker
      openssl
      skopeo
      treefmt
      websocat
    ]
    ++ lib.optionals stdenv.isLinux [ podman ];

  env = {
    GOTOOLCHAIN = "local";
  };
}
