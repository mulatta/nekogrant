{
  dockerTools,
  stdenv,
}:

let
  version = "3.1.5";
  image =
    {
      x86_64-linux = {
        arch = "amd64";
        hash = "sha256-sZ3Z0Ti/PYXP7Qqxbm6w+09Asfld4uQxnUai+62Q/tM=";
      };
      aarch64-linux = {
        arch = "arm64";
        hash = "sha256-BViJWLpb4wfSttjSBjVxorS8YBv1+qZ+6Be1pyNq7/k=";
      };
    }
    .${stdenv.hostPlatform.system};
in
dockerTools.pullImage {
  imageName = "ghcr.io/m1k1o/neko/chromium";
  imageDigest = "sha256:a79093411aced75b3ed7110d50ec9082f9933afabd6592254f01c383678082e7";
  inherit (image) hash arch;
  finalImageTag = version;
  os = "linux";
}
