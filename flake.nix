{
  description = "Pico Green Clock - A firmware for the Waveshare Pico Green Clock";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    pico-sdk = {
      url = "git+https://github.com/raspberrypi/pico-sdk?ref=refs/tags/2.1.0&submodules=1";
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

      # Function to create a build derivation
      mkPicoGreenClock = { variant, enableWifi ? false }: pkgs.stdenv.mkDerivation {
        pname = "pico-green-clock-${variant}";
        version = "10.01";
        
        src = ./.;

        nativeBuildInputs = commonBuildInputs;

        cmakeFlags = [
          "-DPICO_SDK_PATH=${pico-sdk}"
          "-DCMAKE_EXPORT_COMPILE_COMMANDS=1"
          "-DCMAKE_SYSTEM_NAME=Generic"
          "-DCMAKE_C_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc"
          "-DCMAKE_CXX_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-g++"
          "-DCMAKE_ASM_COMPILER=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-gcc"
          (if enableWifi then "-DPICO_BOARD=pico_w" else "-DPICO_BOARD=pico")
        ] ++ (if enableWifi then [
          "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
          "-DFETCHCONTENT_SOURCE_DIR_PICOTOOL=${picotool}"
        ] else [
          "-DPICO_NO_PICOTOOL=ON"
        ]);

        # Set required environment variables
        PICO_SDK_PATH = "${pico-sdk}";
        CMAKE_BUILD_PARALLEL_LEVEL = "4";

        configurePhase = ''
          runHook preConfigure

          # Create symbolic link for pico_sdk_import.cmake
          ln -sf ${pico-sdk}/external/pico_sdk_import.cmake pico_sdk_import.cmake
          
          # Use the existing CMakeLists.txt and modify it for the variant
          ${if enableWifi then ''
            # For Pico W, use CMakeLists.txt as-is (it's already configured for Pico W)
            echo "Using existing CMakeLists.txt for Pico W"
          '' else ''
            # For regular Pico, modify CMakeLists.txt to remove WiFi dependencies
            sed -i 's/set(PICO_BOARD pico_w CACHE STRING "Board type")/set(PICO_BOARD pico CACHE STRING "Board type")/' CMakeLists.txt
            # Remove WiFi-specific source files from add_executable line only
            sed -i 's/picow_ntp_client.c//' CMakeLists.txt
            sed -i 's/ssi.c cgi.c//' CMakeLists.txt
            # Move pico_set_program_name and pico_set_program_version calls after add_executable
            sed -i '/pico_set_program_name/d' CMakeLists.txt
            sed -i '/pico_set_program_version/d' CMakeLists.txt
            sed -i '/add_executable.*)/a\\npico_set_program_name(Pico-Green-Clock "Pico-Green-Clock")\\npico_set_program_version(Pico-Green-Clock "10.01")' CMakeLists.txt
            # Remove WiFi-specific libraries from target_link_libraries
            sed -i '/pico_cyw43_arch_lwip_threadsafe_background/d' CMakeLists.txt
            sed -i '/pico_lwip_http/d' CMakeLists.txt
            # Remove the WiFi include directory
            sed -i '/pico_cyw43_arch\/include/d' CMakeLists.txt
            # Remove WiFi-related includes from the main C file
            sed -i '/#include.*picow_ntp_client.h/d' Pico-Green-Clock.c
            # Comment out the manual PICO_W define for regular Pico builds
            sed -i 's/#define PICO_W/\/\/ #define PICO_W/' Pico-Green-Clock.c
            # Comment out the makefsdata script execution since it's WiFi-related
            sed -i 's/message("Running makefsdata python script")/# message("Running makefsdata python script")/' CMakeLists.txt
            sed -i 's/execute_process(COMMAND/# execute_process(COMMAND/' CMakeLists.txt
            sed -i 's/        python makefsdata.py/# python makefsdata.py/' CMakeLists.txt
            sed -i 's/        WORKING_DIRECTORY $'{CMAKE_CURRENT_LIST_DIR}'/# WORKING_DIRECTORY $'{CMAKE_CURRENT_LIST_DIR}'/' CMakeLists.txt
            sed -i '/python makefsdata.py/,+2s/^)/# )/' CMakeLists.txt
            # Create empty html_files directory and minimal htmldata.c to prevent missing files
            mkdir -p html_files
            cat > htmldata.c << 'EOF'
// Minimal htmldata.c stub for non-WiFi build
static const unsigned char data_stub[] = {0};
const struct fsdata_file file_stub[] = {{ NULL, data_stub, data_stub, sizeof(data_stub), 0}};
#define FS_ROOT file_stub
#define FS_NUMFILES 1
EOF
          ''}

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
          cp build/Pico-Green-Clock.elf $out/bin/${variant}.elf
          # Copy UF2 file if it exists (might not exist for regular Pico build)
          if [ -f build/Pico-Green-Clock.uf2 ]; then
            cp build/Pico-Green-Clock.uf2 $out/bin/${variant}.uf2
          fi
          
          runHook postInstall
        '';

        meta = with pkgs.lib; {
          description = "Firmware for the Waveshare Pico Green Clock";
          homepage = "https://github.com/cmcornish/Pico-Green-Clock";
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
          gdb
          minicom
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