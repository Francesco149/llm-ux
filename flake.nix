{
  description = "llm-ux — Native Desktop Creation Tool Framework & Skills";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.runCommand "llm-ux" { } ''
          mkdir -p $out
          cp -r ${./skills} $out/skills
          cp -r ${./templates} $out/templates
          cp -r ${./tools} $out/tools
          cp -r ${./docs} $out/docs
        '';

        devShells.default = pkgs.mkShell {
          name = "llm-ux-dev";
          packages = with pkgs; [
            python3
            git
          ];
        };
      }
    )
    // {
      templates.default = {
        path = ./templates/raylib;
        description = "CubeForge 2D+3D Raylib creation tool template";
      };
      templates.raylib = {
        path = ./templates/raylib;
        description = "CubeForge 2D+3D Raylib creation tool template";
      };
    };
}
