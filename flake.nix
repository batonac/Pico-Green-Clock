{
  description = "Pico Green Clock - A firmware for the Waveshare Pico Green Clock";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    pico-sdk = {
      url = "git+https://github.com/raspberrypi/pico-sdk?ref=refs/tags/2.0.0&submodules=1";
      flake = false;
    };

    picotool = {
      url = "git+https://github.com/raspberrypi/picotool.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, pico-sdk, picotool }: let
    # System types supported
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    
    # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    
    # Nixpkgs instantiated for supported system types
    nixpkgsFor = forAllSystems (system: import nixpkgs { 
      inherit system; 
      config.allowUnfree = true;
    });
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgsFor.${system};
      
      # Common build inputs for both variants
      commonBuildInputs = with pkgs; [
        cmake
        gcc-arm-embedded
        python3
        pkg-config
        git
      ];

      # Common CMake flags
      commonCMakeFlags = [
        "-DPICO_SDK_PATH=${pico-sdk}"
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=1"
        "-DCMAKE_SYSTEM_NAME=Generic"
        "-DCMAKE_C_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc"
        "-DCMAKE_CXX_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-g++"
        "-DCMAKE_ASM_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc"
        "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
        "-DFETCHCONTENT_SOURCE_DIR_PICOTOOL=${picotool}"
      ];

      # Function to create a build derivation
      mkPicoGreenClock = { variant, enableWifi ? false }: pkgs.stdenv.mkDerivation {
        pname = "pico-green-clock-${variant}";
        version = "10.01";
        
        src = ./.;

        nativeBuildInputs = commonBuildInputs;

        cmakeFlags = commonCMakeFlags ++ [
          (if enableWifi then "-DPICO_BOARD=pico_w" else "-DPICO_BOARD=pico")
        ];

        # Set required environment variables
        PICO_SDK_PATH = "${pico-sdk}";
        CMAKE_BUILD_PARALLEL_LEVEL = "4";

        configurePhase = ''
          runHook preConfigure

          # Create symbolic link for pico_sdk_import.cmake
          ln -sf ${pico-sdk}/external/pico_sdk_import.cmake pico_sdk_import.cmake
          
          # Use the appropriate CMakeLists.txt based on variant
          cp ${if enableWifi then "CMakeLists.txt.PicoW" else "CMakeLists.txt.Pico"} CMakeLists.txt

          # Configure with cmake
          cmake -B build -S . ''${cmakeFlagsArray[@]} ''${cmakeFlags[@]} 

          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild

          cmake --build build -j$CMAKE_BUILD_PARALLEL_LEVEL

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          
          mkdir -p $out/bin
          cp build/Pico-Green-Clock.{elf,uf2} $out/bin/
          
          # Also copy the map file for debugging
          cp build/Pico-Green-Clock.map $out/bin/
          
          runHook postInstall
        '';

        meta = with pkgs.lib; {
          description = "Firmware for the Waveshare Pico Green Clock";
          homepage = "https://github.com/astlouys/Pico-Green-Clock";
          license = licenses.bsd3;
          platforms = platforms.all;
          maintainers = [ ];
        };
      };
    in {
      # Build for regular Pico
      pico = mkPicoGreenClock {
        variant = "pico";
        enableWifi = false;
      };

      # Build for Pico W with WiFi
      picow = mkPicoGreenClock {
        variant = "picow";
        enableWifi = true;
      };

      # Set the default package to the Pico W variant
      default = self.packages.${system}.picow;
    });

    # Development shell with all required build tools
    devShells = forAllSystems (system: let
      pkgs = nixpkgsFor.${system};
    in {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          cmake
          gcc-arm-embedded
          python3
          pkg-config
          git
          
          # Additional development tools
          gdb-multiarch
          minicom
          picotool
        ];

        shellHook = ''
          export PICO_SDK_PATH=${pico-sdk}
          export CMAKE_C_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc
          export CMAKE_CXX_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-g++
          export CMAKE_ASM_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc
          export FETCHCONTENT_SOURCE_DIR_PICOTOOL=${picotool}
          echo "Pico SDK development shell"
          echo "SDK Path: $PICO_SDK_PATH"
        '';
      };
    });
  };
}