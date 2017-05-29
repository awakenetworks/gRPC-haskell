{ mkDerivation, async, base, bytestring, c2hs, clock, containers
, grpc, managed, optparse-generic, pipes, proto3-suite, proto3-wire
, QuickCheck, safe, sorted-list, stdenv, stm, system-filepath
, tasty, tasty-hunit, tasty-quickcheck, text, time, transformers
, turtle, unix, vector
}:
mkDerivation {
  pname = "grpc-haskell";
  version = "0.0.0.0";
  src = ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    async base bytestring clock containers managed pipes proto3-suite
    proto3-wire safe sorted-list stm tasty tasty-hunit tasty-quickcheck
    transformers vector
  ];
  librarySystemDepends = [ grpc ];
  libraryToolDepends = [ c2hs ];
  executableHaskellDepends = [
    async base bytestring containers optparse-generic proto3-suite
    proto3-wire system-filepath text transformers turtle
  ];
  testHaskellDepends = [
    async base bytestring clock containers managed pipes proto3-suite
    QuickCheck safe tasty tasty-hunit tasty-quickcheck text time
    transformers turtle unix
  ];
  homepage = "https://github.com/awakenetworks/gRPC-haskell";
  description = "Haskell implementation of gRPC layered on shared C library";
  license = stdenv.lib.licenses.asl20;
}
