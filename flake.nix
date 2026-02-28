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
      in {

        ##################################
        # 📦 PACKAGE (your app)
        ##################################

        packages.default = pkgs.writeShellApplication {
          name = "cast";

          runtimeInputs = with pkgs; [
            bash
            coreutils
            gleam
            nodejs_22
            rebar3
          ];

          buildInputs = with pkgs; [
            poppler_utils
            libreoffice-fresh
            pngquant
            qrrs
          ];

          text = ''
            #!/usr/bin/env bash
            set -e

            export WEBSOCKET_URL="''${WEBSOCKET_URL:-ws://localhost:8080}"

            echo "🚀 Starting Cast Application"

            trap 'echo "🛑 Shutting down Cast"; jobs -p | xargs -r kill; exit 0' SIGINT SIGTERM

            node $PWD/websocket_relay.js &
            WS_PID=$!

            sleep 2
            kill -0 $WS_PID 2>/dev/null || exit 1

            gleam run &
            GLEAM_PID=$!

            sleep 2
            kill -0 $GLEAM_PID 2>/dev/null || { kill $WS_PID; exit 1; }

            wait
          '';
        };

        ##################################
        # 🚀 APP (what nix run executes)
        ##################################

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/cast";
        };

        ##################################
        # 🧪 DEV SHELL
        ##################################

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gleam
            nodejs_22
            poppler_utils
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
