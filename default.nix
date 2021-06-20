{ stackYaml 
, stackYamlLock ? stackYaml + ".lock"
, pkgs ? import <nixpkgs> {}
}:

with pkgs.lib;
let
  traceId = x: builtins.trace x x;

  fromYamlFile = yamlFile: builtins.fromJSON (builtins.readFile (
    pkgs.stdenv.mkDerivation {
      name = "stack.yaml.lock.json";
      buildInputs = [ pkgs.yaml2json ];
      src = yamlFile;
      buildCommand = ''
        cat $src | yaml2json > $out
      '';
  }));
  stackYamlLockContents = fromYamlFile stackYamlLock;
  snapshotFile = 
    let snapshot = (builtins.head stackYamlLockContents.snapshots);
    in builtins.fetchurl { inherit (snapshot.completed) url sha256; };
  snapshotFileContents = fromYamlFile snapshotFile;
  turnPackageDescriptionIntoPackage = packageYamlContents:
    if builtins.hasAttr "hackage" packageYamlContents
      then 
      let nameVersionAndHash = packageYamlContents.hackage;
          pieces = splitString "@" nameVersionAndHash;
          nameAndVersion = head pieces;
          hashAndSize = last pieces;
          namePieces = splitString "-" nameAndVersion;
          name = concatStringsSep "-" (init namePieces);
          version = last namePieces;
        in nameValuePair name (pkgs.haskellPackages.callHackage name version {})
    else builtins.trace "Not implemented yet." null;
    
  snapshotPackageSet = builtins.listToAttrs (builtins.map turnPackageDescriptionIntoPackage snapshotFileContents.packages);

  stackYamlContents = fromYamlFile stackYaml;

  localPackagePath = builtins.head stackYamlContents.packages;
    
  localPkgDerivation = pkgs.haskellPackages.haskellSrc2nix {
    name = "test";
    src = builtins.dirOf stackYaml + "/${localPackagePath}";
  };

  extraOverrides = {
    inherit (pkgs.stdenv) mkDerivation;
    inherit (pkgs) stdenv;
    base = pkgs.haskellPackages.base;
  };
  localPkg = callPackageWith snapshotPackageSet localPkgDerivation extraOverrides;

  # TODO: We need to generate code like in hackage-packages.nix in nixpkgs
in traceId localPkgDerivation
