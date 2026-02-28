{
  description = "Cast - Remote presentation control system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        castApp = pkgs.writeShellApplication {
          name = "cast";

          runtimeInputs = with pkgs; [
	  erlang
            bash
            coreutils
            nodejs_22
            gleam
            rebar3
            poppler-utils
            libreoffice-fresh
            pngquant
            qrrs
          ];

          text = ''
            set -e

            export WEBSOCKET_URL="''${WEBSOCKET_URL:-ws://localhost:8080}"

            echo "🚀 Starting Cast via start.sh"

            exec ${./start.sh} '';
        };
      in {
        apps.default = {
          type = "app";
          program = "${castApp}/bin/cast";
        };

        packages.default = castApp;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
	  erlang
            gleam
            nodejs_22
            poppler-utils
            libreoffice-fresh
            pngquant
            qrrs
            tailwindcss
            git
            rebar3
          ];
        };
      });
}
