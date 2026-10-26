# Home-manager module: Rutile's settings in Nix (D45). The options are built from settings/schema.json, the
# same schema the shell checks against, so `programs.rutile.settings.motion.speed = 1.5;` is type checked here.
# What you set is written to $XDG_CONFIG_HOME/rutile/managed.json, read-only; the shell gives it priority over
# its own settings.json and does not let those keys change. Options left unset (null) stay the shell's to change.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.rutile;
  json = pkgs.formats.json { };
  schema = builtins.fromJSON (builtins.readFile ../settings/schema.json);

  leafType =
    s:
    if s ? enum then
      lib.types.enum s.enum
    else if s.type == "boolean" then
      lib.types.bool
    else if s.type == "integer" then
      bounded lib.types.int s
    else if s.type == "number" then
      bounded lib.types.number s
    else if s.type == "string" then
      lib.types.str
    else if s.type == "array" then
      lib.types.listOf (leafType s.items)
    else
      throw "rutile: settings/schema.json: unsupported type ${builtins.toJSON s.type}";

  # minimum and maximum, as the shell checks them
  bounded =
    type: s:
    if s ? minimum || s ? maximum then
      lib.types.addCheck type (v: (!(s ? minimum) || v >= s.minimum) && (!(s ? maximum) || v <= s.maximum))
      // {
        description = "${type.description} between ${toString (s.minimum or "-inf")} and ${toString (s.maximum or "inf")}";
      }
    else
      type;

  optionsFor = s: lib.mapAttrs (_: p: if p.type == "object" then optionsFor p else leafOption p) s.properties;
  leafOption =
    p:
    lib.mkOption {
      type = lib.types.nullOr (leafType p);
      default = null;
      description =
        lib.concatStringsSep " " (lib.filter (x: x != "") [ (p.title or "") (p.description or "") ])
        + lib.optionalString (p ? default) " The shell's default: ${builtins.toJSON p.default}.";
    };

  # the settings that were set: no nulls, no empty objects
  prune =
    v:
    lib.filterAttrs (_: x: x != null && x != { }) (
      lib.mapAttrs (_: x: if builtins.isAttrs x then prune x else x) v
    );
  managed = prune cfg.settings;
in
{
  options.programs.rutile.settings = optionsFor schema;

  config = lib.mkIf (managed != { }) {
    xdg.configFile."rutile/managed.json".source = json.generate "rutile-managed.json" managed;
  };
}
