{ lib }:

let
  decimalPortIsValid =
    port:
    port == null
    || (
      lib.stringLength port <= 5
      && builtins.match "^[0-9]+$" port != null
      && (
        let
          value = lib.toInt port;
        in
        value >= 1 && value <= 65535
      )
    );
  hostnameIsValid =
    hostname:
    hostname != ""
    && lib.stringLength hostname <= 253
    && lib.all (
      label:
      label != ""
      && lib.stringLength label <= 63
      && builtins.match "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$" label != null
    ) (lib.splitString "." hostname);
  registryAuthorityIsValid =
    authority:
    let
      bracketed = builtins.match "^[[]([^]]+)[]](:([0-9]+))?$" authority;
      plain = builtins.match "^([^:]+)(:([0-9]+))?$" authority;
    in
    if bracketed != null then
      let
        address = builtins.elemAt bracketed 0;
      in
      lib.hasInfix ":" address
      && addressIsValid address
      && decimalPortIsValid (builtins.elemAt bracketed 2)
    else
      plain != null
      && (
        let
          host = builtins.elemAt plain 0;
        in
        (addressIsValid host || hostnameIsValid host) && decimalPortIsValid (builtins.elemAt plain 2)
      );
  repositoryComponentIsValid =
    component:
    component != ""
    && lib.stringLength component <= 255
    && builtins.match "^[a-z0-9]+(([._]|__|[-]+)[a-z0-9]+)*$" component != null;
  imageNameIsValid =
    name:
    let
      components = lib.splitString "/" name;
      first = if components == [ ] then "" else builtins.head components;
      hasRegistry =
        lib.length components > 1
        && (first == "localhost" || lib.hasInfix "." first || lib.hasInfix ":" first);
      repository = if hasRegistry then builtins.tail components else components;
    in
    components != [ ]
    && lib.stringLength name <= 255
    && (!hasRegistry || registryAuthorityIsValid first)
    && repository != [ ]
    && lib.all repositoryComponentIsValid repository;
  imageReferenceIsValid =
    reference:
    let
      digestParts = lib.splitString "@" reference;
      hasDigest = lib.length digestParts == 2;
      referenceWithoutDigest = if digestParts == [ ] then "" else builtins.head digestParts;
      digest = if hasDigest then builtins.elemAt digestParts 1 else null;
      pathComponents = lib.splitString "/" referenceWithoutDigest;
      lastComponent = if pathComponents == [ ] then "" else lib.last pathComponents;
      tagParts = lib.splitString ":" lastComponent;
      hasTag = lib.length tagParts == 2;
      tag = if hasTag then builtins.elemAt tagParts 1 else null;
      name =
        if hasTag then
          lib.concatStringsSep "/" ((lib.init pathComponents) ++ [ (builtins.head tagParts) ])
        else
          referenceWithoutDigest;
    in
    lib.length digestParts <= 2
    && imageNameIsValid name
    && (
      if hasDigest then
        !hasTag && builtins.match "^sha256:[0-9a-f]{64}$" digest != null
      else
        hasTag && builtins.match "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$" tag != null
    );
  retrievalUrlIsValid =
    url:
    let
      isHttps = lib.hasPrefix "https://" url;
      isHttp = lib.hasPrefix "http://" url;
      withoutScheme =
        if isHttps then
          lib.removePrefix "https://" url
        else if isHttp then
          lib.removePrefix "http://" url
        else
          "";
      pathParts = lib.splitString "/" withoutScheme;
      authority = if pathParts == [ ] then "" else builtins.head pathParts;
      bracketed = builtins.match "^[[]([^]]+)[]](:([0-9]+))?$" authority;
      plain = builtins.match "^([^:]+)(:([0-9]+))?$" authority;
      authorityIsValid =
        if bracketed != null then
          let
            address = builtins.elemAt bracketed 0;
          in
          lib.hasInfix ":" address
          && addressIsValid address
          && decimalPortIsValid (builtins.elemAt bracketed 2)
        else
          plain != null
          && (
            let
              host = builtins.elemAt plain 0;
            in
            (addressIsValid host || hostnameIsValid host) && decimalPortIsValid (builtins.elemAt plain 2)
          );
    in
    (isHttps || isHttp)
    && builtins.match "^[^[:space:]?#@]+$" url != null
    && authority != ""
    && authorityIsValid;

  stripAddressBrackets =
    address:
    if lib.hasPrefix "[" address && lib.hasSuffix "]" address then
      lib.removeSuffix "]" (lib.removePrefix "[" address)
    else
      address;
  parseAddress =
    address:
    let
      stripped = stripAddressBrackets address;
      isIPv6 = lib.hasInfix ":" stripped;
      isUnscopedHostAddress = !(lib.hasInfix "/" stripped) && !(lib.hasInfix "%" stripped);
      ipv4Parts = lib.splitString "." stripped;
      validIPv4Part = part: builtins.match "^(0|[1-9][0-9]{0,2})$" part != null && lib.toInt part <= 255;
      validIPv4 = lib.length ipv4Parts == 4 && lib.all validIPv4Part ipv4Parts;
      parsedIPv6 = (lib.network.ipv6.fromString stripped).address;
      ipv6Attempt = builtins.tryEval (builtins.deepSeq parsedIPv6 parsedIPv6);
    in
    if isIPv6 then
      {
        inherit isIPv6;
        success = isUnscopedHostAddress && ipv6Attempt.success;
        normalized = if isUnscopedHostAddress && ipv6Attempt.success then ipv6Attempt.value else stripped;
      }
    else
      {
        inherit isIPv6;
        success = validIPv4;
        normalized = stripped;
      };
  addressIsValid = address: (parseAddress address).success;
  normalizeAddress = address: (parseAddress address).normalized;
  formatBindAddress =
    address:
    let
      normalized = normalizeAddress address;
    in
    if lib.hasInfix ":" normalized then "[${normalized}]" else normalized;
  ipv6AnyAddress = normalizeAddress "::";
  addressesOverlap =
    left: right:
    left == right
    || (
      lib.hasInfix ":" left
      && lib.hasInfix ":" right
      && (left == ipv6AnyAddress || right == ipv6AnyAddress)
    )
    || (
      !(lib.hasInfix ":" left) && !(lib.hasInfix ":" right) && (left == "0.0.0.0" || right == "0.0.0.0")
    );
  absolutePathIsLexicallyClean =
    path:
    lib.hasPrefix "/" path
    && path != "/"
    && !(lib.hasSuffix "/" path)
    && builtins.match "^/[A-Za-z0-9._/-]+$" path != null
    && !(lib.hasInfix "//" path)
    && lib.all (segment: segment != "." && segment != "..") (lib.splitString "/" path);
in
{
  inherit
    addressIsValid
    addressesOverlap
    absolutePathIsLexicallyClean
    formatBindAddress
    imageReferenceIsValid
    ipv6AnyAddress
    normalizeAddress
    retrievalUrlIsValid
    ;
}
