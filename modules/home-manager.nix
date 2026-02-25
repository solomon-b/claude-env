flake:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.claude-env;
in
{
  options.programs.claude-env = {
    enable = lib.mkEnableOption "claude-env, a multi-environment manager for Claude Code";

    package = lib.mkOption {
      type = lib.types.package;
      default = flake.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "The claude-env package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.bash.initExtra = ''
      source ${cfg.package}/share/claude-env/claude-env.sh
    '';

    programs.zsh.initExtra = ''
      source ${cfg.package}/share/claude-env/claude-env.sh
    '';
  };
}
