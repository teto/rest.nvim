{ buildLuarocksPackage, fetchurl, fetchzip, luaOlder, luarocks-build-treesitter-parser }:
buildLuarocksPackage {
  pname = "tree-sitter-http";
  version = "0.0.31-1";
  knownRockspec = (fetchurl {
    url    = "mirror://luarocks/tree-sitter-http-0.0.31-1.rockspec";
    sha256 = "1kp1n0q1v2nkc8nckgy8wjp71jy5ycskma5s6p01b4x7z8yp6b04";
  }).outPath;
  src = fetchzip {
    url    = "https://github.com/rest-nvim/tree-sitter-http/archive/231f1b1bafd12e46c8ed8c21dbbdd940d9f15e94.zip";
    sha256 = "1k6vj0ml90l0hc3qj05hhkzyrf437cf594dgprsgk99dfyxkpj5b";
  };

  disabled = luaOlder "5.1";
  nativeBuildInputs = [ luarocks-build-treesitter-parser ];

  meta = {
    homepage = "https://github.com/rest-nvim/tree-sitter-http";
    description = "tree-sitter parser for http";
    license.fullName = "UNKNOWN";
  };
}
