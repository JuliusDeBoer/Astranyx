{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs
  }: let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
    };
  in {
    devShell.x86_64-linux = pkgs.mkShell {
      buildInputs = with pkgs; [
        gdb
        shaderc
        vulkan-headers
        vulkan-loader
        vulkan-validation-layers
        wayland
        zig
        zls
      ];
      shellHook = ''
        export VK_LAYER_PATH="${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
      '';
    };
  };
}
