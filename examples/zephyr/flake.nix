{
  description = "SDK for Zephyr";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Pin the Zephyr tree you want to work with
    zephyr.url = "github:zephyrproject-rtos/zephyr/v3.5.0";
    zephyr.flake = false;

    # Your helper overlay/package set
    zephyr-nix.url = "github:ge0053/zephyr-nix";
    zephyr-nix.inputs.nixpkgs.follows = "nixpkgs";
    zephyr-nix.inputs.zephyr.follows = "zephyr";
  };

  outputs = {
    self,
    nixpkgs,
    zephyr-nix,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        zpkgs = zephyr-nix.packages.${system};

        # Use unwrapped clang to avoid nix cc-wrapper injecting bad flags
        llvm = pkgs.llvmPackages_20;

        # Build & host tools (no zephyr-sdk here)
        hostTools = [
          pkgs.cmake
          pkgs.ninja
          pkgs.gperf # Zephyr build requires this
          pkgs.dtc # Device tree compiler (if not provided by zpkgs.hosttools)
          pkgs.openocd # Optional, for flashing/debug
          pkgs.stlink # Optional, ST-LINK
          pkgs.qemu # Optional, qemu-system-arm
        ];

        llvmTools = [
          llvm.clang-unwrapped
          llvm.lld
          llvm.llvm # llvm-objcopy/objdump/ar/nm/strip/size/etc.
        ];
      in {
        formatter = pkgs.alejandra;

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            zpkgs.sdkFull-0_16
            zpkgs.pythonEnv
            zpkgs.hosttools
            pkgs.cmake
            pkgs.ninja
            pkgs.newlib # C library headers for bare-metal ARM
          ];
        };
        #TODO: make it work correctly
        devShells.llvm = pkgs.mkShell {
          name = "zephyr-llvm-non-sdk";

          # Python env with west and common Zephyr python deps
          nativeBuildInputs =
            llvmTools
            ++ hostTools
            ++ [
              zpkgs.pythonEnv # west, pyelftools, pyyaml, etc.
              zpkgs.hosttools # extra Zephyr host tools (dtc, etc.) if provided
            ];

          shellHook = ''
            echo ">>> Zephyr + LLVM environment (no Zephyr SDK)"

            # Make sure unwrapped LLVM tools dominate PATH
            export PATH="${llvm.clang-unwrapped}/bin:${llvm.lld}/bin:${llvm.llvm}/bin:$PATH"

            # Tell Zephyr to use LLVM/Clang
            export ZEPHYR_TOOLCHAIN_VARIANT=llvm

            # Tool names Zephyr expects for the LLVM variant
            export CC=clang
            export CXX=clang++
            export AS=clang
            export LD=ld.lld
            export AR=llvm-ar
            export NM=llvm-nm
            export OBJCOPY=llvm-objcopy
            export OBJDUMP=llvm-objdump
            export STRIP=llvm-strip
            export SIZE=llvm-size
            export PATH="${pkgs.llvmPackages_20.lld}/bin:${pkgs.llvmPackages_20.clang-unwrapped}/bin:$PATH"
            export CMAKE_LINKER=${pkgs.llvmPackages_20.lld}
            export CMAKE_C_LINKER=${pkgs.llvmPackages_20.lld}
            export CMAKE_CXX_LINKER=${pkgs.llvmPackages_20.lld}
            # Very important: prevent this
            unset CMAKE_C_COMPILER_WRAPPER
            unset CMAKE_CXX_COMPILER_WRAPPER

            # Quality-of-life
            export CMAKE_EXPORT_COMPILE_COMMANDS=1

            # Debug info
            echo "clang: $(which clang)"
            echo "ld.lld: $(which ld.lld)"
          '';
        };
      }
    );
  #west build -b adi_eval_adin1110ebz --   -DCMAKE_LINKER=ld.lld   -DCMAKE_C_LINKER=ld.lld   -DCMAKE_CXX_LINKER=ld.lld   -DCMAKE_ASM_LINKER=ld.lld   -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld"   -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld"   -DCMAKE_MODULE_LINKER_FLAGS="-fuse-ld=lld"
}
