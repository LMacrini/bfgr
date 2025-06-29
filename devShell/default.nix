{pkgs, lib, stdenv, ...}: let
  linuxLibs = with pkgs; [
    libGL
    xorg.libX11
    xorg.libXcursor
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXinerama
    xorg.libXrandr
    xorg.libXrender
    mesa
    wayland
    libxkbcommon
  ];

  linuxPkgs = with pkgs; [
    wayland-scanner
  ] ++ linuxLibs;
in pkgs.mkShell {
  name = "bfgr";

  packages = with pkgs; [
    zig
  ] ++ linuxPkgs;

  LDD_LIBRARY_PATH = if stdenv.isLinux then lib.makeLibraryPath linuxLibs else null;
}
