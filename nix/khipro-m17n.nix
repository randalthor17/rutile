# Khipro (dark), a compositional Bengali input method, as an m17n input method (D125): the .mim and its icon, in
# share/m17n. MIT, https://github.com/KhiproTeam/khipro-dark-m17n. m17n finds it in the user's ~/.m17n.d, where
# the home-manager module links it, and fcitx5-m17n then lists it with the others.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "khipro-dark-m17n";
  version = "0-unstable-2026-10-27";

  src = fetchFromGitHub {
    owner = "KhiproTeam";
    repo = "khipro-dark-m17n";
    rev = "42db90d15faf7d219e6581b8cd340e534c248dda";
    hash = "sha256-Gg36YSLvx48Ai/wJIrsHp9cpZR4PZ/mE51guuVmoM5E=";
  };

  installPhase = ''
    runHook preInstall
    install -Dm644 bn-khipro-dark.mim $out/share/m17n/bn-khipro-dark.mim
    install -Dm644 bn-khipro-dark.png $out/share/m17n/icons/bn-khipro-dark.png
    runHook postInstall
  '';

  meta = {
    description = "Khipro, a compositional Bengali input method, for m17n";
    homepage = "https://github.com/KhiproTeam/khipro-dark-m17n";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
