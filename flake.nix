{
  description = "Pico Green Clock - Enhanced firmware for Waveshare's Pico Green Clock";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Add pico-sdk as a non-flake input
    pico-sdk = {
      url = "github:raspberrypi/pico-sdk/1.5.1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, pico-sdk }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # The main package derivation
        pico-green-clock = pkgs.stdenv.mkDerivation {
          pname = "pico-green-clock";
          version = "10.01";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            cmake
            gcc-arm-embedded
            python3
            pkg-config
          ];

          # Create the build directory and build the project
          buildPhase = ''
            # Ensure build directory exists
            mkdir -p build
            cd build

            # Create necessary symbolic link
            ln -s ${pico-sdk}/external/pico_sdk_import.cmake ../pico_sdk_import.cmake

            # Configure and build
            export PICO_SDK_PATH=${pico-sdk}
            cmake ..
            make -j $NIX_BUILD_CORES
          '';

          # Install the built files
          installPhase = ''
            mkdir -p $out/bin
            cp Pico-Clock-Green.uf2 $out/bin/
            cp Pico-Clock-Green.elf $out/bin/
            
            # Copy documentation if present
            if [ -f ../README.md ]; then
              mkdir -p $out/share/doc
              cp ../README.md $out/share/doc/
            fi
          '';

          meta = with pkgs.lib; {
            description = "Enhanced firmware for Waveshare's Pico Green Clock";
            homepage = "https://github.com/astlouys/Pico-Green-Clock";
            platforms = platforms.all;
          };
        };

      in {
        packages = {
          inherit pico-green-clock;
          default = pico-green-clock;
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Basic build tools
            cmake
            gcc
            gcc-arm-embedded
            gnumake
            python3

            # Additional tools
            git
            pkg-config
            usbutils

            # Development tools
            gdb-multiarch
            openocd
          ];

          shellHook = ''
            export PICO_SDK_PATH=${pico-sdk}
            
            # Create symbolic link for pico_sdk_import.cmake if it doesn't exist
            if [ ! -f pico_sdk_import.cmake ]; then
              ln -s $PICO_SDK_PATH/external/pico_sdk_import.cmake pico_sdk_import.cmake
            fi

            echo "Pico development environment ready!"
            echo "PICO_SDK_PATH is set to: $PICO_SDK_PATH"
            echo ""
            echo "To build the project:"
            echo "1. mkdir -p build"
            echo "2. cd build"
            echo "3. cmake .."
            echo "4. make -j$NIX_BUILD_CORES"
          '';
        };
      }
    );
}