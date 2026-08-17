{
  description = "godot-blockout — CSG 3D level blockout editor with Godot-grade viewport controls and 1-click .tscn/.glb export";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        mingw = pkgs.pkgsCross.mingwW64.buildPackages;
        mingwPkgs = pkgs.pkgsCross.mingwW64;

        imguiSrc = pkgs.fetchFromGitHub {
          owner = "ocornut";
          repo = "imgui";
          rev = "v1.92.4";
          hash = "sha256-DyQ2fh749S41UFdLto7TtxsnBsd7CBzAUFq36LeZZ5Y=";
        };

        luaSrc = pkgs.runCommand "lua-5.4-src" { } ''
          mkdir -p $out
          tar xzf ${pkgs.lua5_4.src} --strip-components=1 -C $out
        '';
      in {
        devShells.default = pkgs.mkShell {
          name = "godot-blockout-dev";

          packages = with pkgs; [
            mingw.gcc
            mingw.binutils
            gnumake
            pkg-config
            python3
            stb
            lua5_4
            git
          ];

          buildInputs = with pkgs; [ sdl3 libGL mesa ];

          shellHook = ''
            export GB_ROOT=$PWD
            export IMGUI_DIR=${imguiSrc}
            export LUA_SRC=${luaSrc}
            export STB_INC=${pkgs.stb}/include

            export SDL3_CROSS_INC=${mingwPkgs.sdl3.dev}/include
            export SDL3_CROSS_LIB=${mingwPkgs.sdl3}/lib
            export SDL3_CROSS_DLL=${mingwPkgs.sdl3.out}/bin/SDL3.dll

            export MCFG_LIBDIR=$(x86_64-w64-mingw32-g++ -### -x c++ /dev/null -o /dev/null 2>&1 \
              | tr ' ' '\n' | grep -m1 -oE '^-L/nix/store/[^ ]*mcfgthread[^ ]*/lib' | cut -c3-)
            export MCFG_DLL=$(dirname "$MCFG_LIBDIR")/bin/libmcfgthread-2.dll

            export MINGW_CC=x86_64-w64-mingw32-gcc
            export MINGW_CXX=x86_64-w64-mingw32-g++

            echo "godot-blockout dev shell ready"
          '';
        };

        formatter = pkgs.nixfmt-rfc-style;
      });
}
