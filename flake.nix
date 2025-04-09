{
  inputs = {
    utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, utils }: utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {

      packages.default = self.packages.${system}.razzle-nvim;

      packages.razzle-nvim = pkgs.vimUtils.buildVimPlugin {
        pname = "razzle-vim";
        version = "0.0.1";
        src = ./.;
        # contains an optional dependency, so fails the requires check
        nvimSkipModules = [ "razzle.zen-mode" ];
      };

    }
  );
}
