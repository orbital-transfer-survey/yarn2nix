{ pkgs ? import ../../nixpkgs-pinned.nix {}
, nixLibPath ? ../../nix-lib
, yarn2nix ? import ../../. { inherit pkgs; }
}:
let
  nixLib = pkgs.callPackage nixLibPath {
    inherit yarn2nix;
  };

  inherit (import vendor/runTestsuite.nix { inherit pkgs; })
    runTestsuite
    it
    assertEq
    ;

  # small test package.json
  my-package-json = pkgs.writeText "package.json" (builtins.toJSON {
    name = "my-package";
    version = "1.5.3";
    license = "MIT";
  });

  # convert a package.json to yarn2nix package template
  template = package-json: pkgs.runCommandLocal "generate-template" {} ''
    ${yarn2nix}/bin/yarn2nix --license-data ${yarn2nix.passthru.licensesJson} \
      --template ${package-json} > $out
    echo "template for ${package-json} is:" >&2
    cat $out >&2
  '';

  # generates nix expression for license with a given spdx id and imports it
  spdxLicenseSet = spdx:
    let
      packageJson = pkgs.writeText "package.json" (builtins.toJSON {
        name = "license-test-${spdx}";
        version = "0.1.0";
        license = spdx;
      });
      tpl = import (template packageJson) {} {};
    in tpl.meta.license;

  # test suite
  tests = runTestsuite "yarn2nix" [
    (it "checks the template output"
      (let tmpl = import (template my-package-json) {} {};
      in [
      # TODO: this is a naïve match, might want to create a better test
      (assertEq "template" tmpl {
        key = {
          name = "my-package";
          scope = "";
        };
        version = "1.5.3";
        nodeBuildInputs = [];
        meta = {
          license = pkgs.lib.licenses.mit;
        };
      })
    ]))
    (it "checks license conversion"
      (builtins.map
        (v: assertEq v.spdx (spdxLicenseSet v.spdx) v.set)
        (with pkgs.lib.licenses; [
          # TODO recommended attribute name changes in more recent nixpkgs
          { spdx = "AGPL-3.0-only"; set = agpl3; }
          { spdx = "GPL-3.0-or-later"; set = gpl3Plus; }
          { spdx = "MIT"; set = mit; }
          { spdx = "BSD-3-Clause"; set = bsd3; }
          { spdx = "ISC"; set = isc; }
          { spdx = "UNLICENSED"; set = unfree; }
          # Check that anything else is kept as is
          { spdx = "See LICENSE.txt"; set = "See LICENSE.txt"; }
    ])))
  ];

  # small helper that checks the output of tests
  # and pretty-prints errors if there were any
  runTests = pkgs.runCommandLocal "run-tests" {
    testOutput = builtins.toJSON tests;
    passAsFile = [ "testOutput" ];
  }
    (if tests == {}
     then ''touch $out''
     else ''
       echo "ERROR: some tests failed:" >&2
       cat "$testOutputPath" | ${pkgs.jq}/bin/jq >&2
       exit 1
     '');

in {
  inherit runTests;
  testOverriding = import ./test-overriding.nix {
    inherit pkgs nixLib yarn2nix;
  };
}
