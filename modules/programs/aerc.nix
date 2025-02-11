{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.programs.aerc;
  primitive = with types;
    ((type: either type (listOf type)) (nullOr (oneOf [ str int bool float ])))
    // {
      description =
        "values (null, bool, int, string of float) or a list of values, that will be joined with a comma";
    };
  confSection = types.attrsOf primitive;
  confSections = types.attrsOf confSection;
  sectionsOrLines = types.either types.lines confSections;
  accounts = import ./aerc-accounts.nix {
    inherit config pkgs lib confSection confSections;
  };
  aerc-accounts =
    attrsets.filterAttrs (_: v: v.aerc.enable) config.accounts.email.accounts;
in {
  meta.maintainers = with lib.hm.maintainers; [ lukasngl ];

  options.accounts.email.accounts = accounts.type;
  options.programs.aerc = {

    enable = mkEnableOption "aerc";

    extraAccounts = mkOption {
      type = sectionsOrLines;
      default = { };
      example = literalExpression
        ''{ Work = { source = "maildir://~/Maildir/work"; }; }'';
      description = ''
        Extra lines added to <filename>$HOME/.config/aerc/accounts.conf</filename>.
        See aerc-config(5).
      '';
    };

    extraBinds = mkOption {
      type = sectionsOrLines;
      default = { };
      example = literalExpression ''{ messages = { q = ":quit<Enter>"; }; }'';
      description = ''
        Extra lines added to <filename>$HOME/.config/aerc/binds.conf</filename>.
        Global keybindings can be set in the `global` section.
        See aerc-config(5).
      '';
    };

    extraConfig = mkOption {
      type = sectionsOrLines;
      default = { };
      example = literalExpression ''{ ui = { sort = "-r date"; }; }'';
      description = ''
        Extra lines added to <filename>$HOME/.config/aerc/aerc.conf</filename>.
        See aerc-config(5).
      '';
    };

    stylesets = mkOption {
      type = with types; attrsOf (either confSection lines);
      default = { };
      example = literalExpression ''
        { default = { ui = { "tab.selected.reverse" = toggle; }; }; };
      '';
      description = ''
        Stylesets added to <filename>$HOME/.config/aerc/stylesets/</filename>.
        See aerc-stylesets(7).
      '';
    };
    templates = mkOption {
      type = with types; attrsOf lines;
      default = { };
      example = literalExpression ''
        { new_message = "Hello!"; };
      '';
      description = ''
        Templates added to <filename>$HOME/.config/aerc/templates/</filename>.
        See aerc-templates(7).
      '';
    };
  };

  config = let
    joinCfg = cfgs:
      with builtins;
      concatStringsSep "\n" (filter (v: v != "") cfgs);
    toINI = conf: # quirk: global section is prepended w/o section heading
      let
        global = conf.global or { };
        local = removeAttrs conf [ "global" ];
        optNewLine = if global != { } && local != { } then "\n" else "";
        mkValueString = v:
          with builtins;
          if isList v then # join with comma
            concatStringsSep "," (map (generators.mkValueStringDefault { }) v)
          else
            generators.mkValueStringDefault { } v;
        mkKeyValue =
          generators.mkKeyValueDefault { inherit mkValueString; } " = ";
      in joinCfg [
        (generators.toKeyValue { inherit mkKeyValue; } global)
        (generators.toINI { inherit mkKeyValue; } local)
      ];
    mkINI = conf: if builtins.isString conf then conf else toINI conf;
    mkStyleset = attrsets.mapAttrs' (k: v:
      let value = if builtins.isString v then v else toINI { global = v; };
      in {
        name = "aerc/stylesets/${k}";
        value.text = joinCfg [ header value ];
      });
    mkTemplates = attrsets.mapAttrs' (k: v: {
      name = "aerc/templates/${k}";
      value.text = v;
    });
    accountsExtraAccounts = builtins.mapAttrs accounts.mkAccount aerc-accounts;
    accountsExtraConfig =
      builtins.mapAttrs accounts.mkAccountConfig aerc-accounts;
    accountsExtraBinds =
      builtins.mapAttrs accounts.mkAccountBinds aerc-accounts;
    joinContextual = contextual:
      with builtins;
      joinCfg (map mkINI (attrValues contextual));
    header = ''
      # Generated by Home Manager.
    '';
  in mkIf cfg.enable {
    warnings = if ((cfg.extraAccounts != "" && cfg.extraAccounts != { })
      || accountsExtraAccounts != { })
    && (cfg.extraConfig.general.unsafe-accounts-conf or false) == false then [''
      aerc: An email account was configured, but `extraConfig.general.unsafe-accounts-conf` is set to false or unset.
      This will prevent aerc from starting, see `unsafe-accounts-conf` in aerc-config(5) for details.
      Consider setting the option `extraConfig.general.unsafe-accounts-conf` to true.
    ''] else
      [ ];
    home.packages = [ pkgs.aerc ];
    xdg.configFile = {
      "aerc/accounts.conf" = mkIf
        ((cfg.extraAccounts != "" && cfg.extraAccounts != { })
          || accountsExtraAccounts != { }) {
            text = joinCfg [
              header
              (mkINI cfg.extraAccounts)
              (mkINI accountsExtraAccounts)
            ];
          };
      "aerc/aerc.conf" =
        mkIf (cfg.extraConfig != "" && cfg.extraConfig != { }) {
          text = joinCfg [
            header
            (mkINI cfg.extraConfig)
            (joinContextual accountsExtraConfig)
          ];
        };
      "aerc/binds.conf" = mkIf ((cfg.extraBinds != "" && cfg.extraBinds != { })
        || accountsExtraBinds != { }) {
          text = joinCfg [
            header
            (mkINI cfg.extraBinds)
            (joinContextual accountsExtraBinds)
          ];
        };
    } // (mkStyleset cfg.stylesets) // (mkTemplates cfg.templates);
  };
}
