{
  description = "claude-env: Multi-environment manager for Claude Code";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    claude-code.url = "github:sadjow/claude-code-nix";
  };

  outputs = { self, nixpkgs, claude-code }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems f;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "claude-env";
            version = "0.1.0";
            src = ./.;

            dontBuild = true;

            installPhase = ''
              mkdir -p $out/share/claude-env
              cp claude-env.sh $out/share/claude-env/claude-env.sh
            '';

            meta = {
              description = "Multi-environment manager for Claude Code";
              license = pkgs.lib.licenses.mit;
            };
          };
        });

      homeManagerModules.default = import ./modules/home-manager.nix self;

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              claude-code.packages.${system}.claude-code
            ];
          };
        });
    };
}
