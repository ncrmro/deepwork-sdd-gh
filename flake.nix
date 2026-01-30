{
  description = "Deepwork Permanent Portfolio - Automated portfolio analysis using Harry Browne's strategy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    deepwork = {
      url = "github:Unsupervisedcom/deepwork/copilot/implement-plan-md";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, deepwork }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Deepwork CLI from PR #140 branch (manages its own uv/python)
            deepwork.packages.${system}.default

            # Git for version control
            pkgs.git

            # CLI tools
            pkgs.gh
            pkgs.claude-code
          ];
        };
      }
    );
}
