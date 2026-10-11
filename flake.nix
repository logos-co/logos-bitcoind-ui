{
  description = "Logos bitcoind_ui: run and manage a local Bitcoin node (Bitcoin Core).";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    bitcoind_module = {
      url = "github:logos-co/logos-bitcoind-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
