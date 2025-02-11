{
  self,
  inputs,
}: final: prev: let
  mkNeorocksTest = name: nvim:
    with final; neorocksTest {
      inherit name;
      pname = "rest.nvim";
      src = self;
      neovim = nvim;
      luaPackages = ps:
        with ps; [
          nvim-nio
          mimetypes
          xml2lua
          fidget-nvim
          final.lua51Packages.tree-sitter-http
        ];
      extraPackages = [
        jq
      ];

      preCheck = ''
        # Neovim expects to be able to create log files, etc.
        export HOME=$(realpath .)
        export TREE_SITTER_HTTP_PLUGIN_DIR=${final.tree-sitter-http-plugin}
        export REST_NVIM_PLUGIN_DIR=${final.rest-nvim-dev}
      '';
    };
in {
  docgen = final.writeShellApplication {
    name = "docgen";
    runtimeInputs = [
      inputs.vimcats.packages.${final.system}.default
    ];
    text = /* bash */ ''
      mkdir -p doc
      vimcats lua/rest-nvim/{init,commands,autocmds,config/init}.lua > doc/rest-nvim.txt
      vimcats lua/rest-nvim/{api,client/init,parser/init,script/init,cookie_jar,utils,logger}.lua > doc/rest-nvim-api.txt
      vimcats lua/rest-nvim/client/curl/{cli,utils}.lua > doc/rest-nvim-client-curl.txt
    '';
  };
  integration-stable = mkNeorocksTest "integration-stable" final.neovim;
  integration-nightly = mkNeorocksTest "integration-nightly" final.neovim-nightly;
}
