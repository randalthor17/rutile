# NixOS module: run Ollama as a system service on the AMD GPU, for the local side-work agent.
#
#   inputs.rutile.url = "path:/home/you/Downloads/rutile";           # or wherever the repo lives
#   modules = [ rutile.nixosModules.local-ai ];
#
# Tuned for a 16 GB Radeon RX 9060 XT (RDNA4, gfx1200). The ROCm build is selected through
# services.ollama.package. If ROCm misbehaves on the card, switch to the Vulkan build with
#   services.ollama.package = pkgs.ollama-vulkan;
# The environment mirrors tools/local_models.json (tests keep the two in sync).
{ lib, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    package = lib.mkDefault pkgs.ollama-rocm;
    environmentVariables = {
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_CONTEXT_LENGTH = "32768";
    };
  };
}
