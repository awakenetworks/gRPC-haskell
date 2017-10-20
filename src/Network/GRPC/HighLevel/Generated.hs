
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE OverloadedStrings #-}

module Network.GRPC.HighLevel.Generated (
  -- * Types
  MetadataMap(..)
, MethodName(..)
, GRPCMethodType(..)
, GRPCImpl(..)
, MkHandler
, Host(..)
, Port(..)
, StatusDetails(..)
, StatusCode(..)
, GRPCIOError(..)

  -- * Server
, ServiceOptions(..)
, defaultServiceOptions
, ServerCall(..)
, serverCallCancel
, serverCallIsExpired
, ServerRequest(..)
, ServerResponse(..)

  -- * Server Auth
, ServerSSLConfig(..)

  -- * Client
, withGRPCClient
, ClientConfig(..)
, ClientError(..)
, ClientRequest(..)
, ClientResult(..)
)
where

import           Network.GRPC.HighLevel.Server
import           Network.GRPC.HighLevel.Client
import           Network.GRPC.LowLevel
import           Network.GRPC.LowLevel.Call
import           System.IO (hPutStrLn, stderr)

-- | Used at the kind level as a parameter to service definitions
--   generated by the grpc compiler, with the effect of having the
--   field types reduce to the appropriate types for the method types.
data GRPCImpl = ServerImpl | ClientImpl

-- | GHC does not let us partially apply a type family. However, we
--   can define a type to use as an 'interpreter', and then use this
--   'interpreter' type fully applied to get the same effect.
type family MkHandler (impl :: GRPCImpl) (methodType :: GRPCMethodType) i o

type instance MkHandler 'ServerImpl 'Normal          i o = ServerHandler       i o
type instance MkHandler 'ServerImpl 'ClientStreaming i o = ServerReaderHandler i o
type instance MkHandler 'ServerImpl 'ServerStreaming i o = ServerWriterHandler i o
type instance MkHandler 'ServerImpl 'BiDiStreaming   i o = ServerRWHandler     i o

-- | Options for a service that was generated from a .proto file. This is
-- essentially 'ServerOptions' with the handler fields removed.
data ServiceOptions = ServiceOptions
  { serverHost           :: Host
    -- ^ Name of the host the server is running on.
  , serverPort           :: Port
    -- ^ Port on which to listen for requests.
  , useCompression       :: Bool
    -- ^ Whether to use compression when communicating with the client.
  , userAgentPrefix      :: String
    -- ^ Optional custom prefix to add to the user agent string.
  , userAgentSuffix      :: String
    -- ^ Optional custom suffix to add to the user agent string.
  , initialMetadata      :: MetadataMap
    -- ^ Metadata to send at the beginning of each call.
  , sslConfig            :: Maybe ServerSSLConfig
    -- ^ Security configuration.
  , logger               :: String -> IO ()
    -- ^ Logging function to use to log errors in handling calls.
  }

defaultServiceOptions :: ServiceOptions
defaultServiceOptions = ServiceOptions
  -- names are fully qualified because we use the same fields in LowLevel.
  { Network.GRPC.HighLevel.Generated.serverHost      = "localhost"
  , Network.GRPC.HighLevel.Generated.serverPort      = 50051
  , Network.GRPC.HighLevel.Generated.useCompression  = False
  , Network.GRPC.HighLevel.Generated.userAgentPrefix = "grpc-haskell/0.0.0"
  , Network.GRPC.HighLevel.Generated.userAgentSuffix = ""
  , Network.GRPC.HighLevel.Generated.initialMetadata = mempty
  , Network.GRPC.HighLevel.Generated.sslConfig       = Nothing
  , Network.GRPC.HighLevel.Generated.logger          = hPutStrLn stderr
  }

withGRPCClient :: ClientConfig -> (Client -> IO a) -> IO a
withGRPCClient c f = withGRPC $ \grpc -> withClient grpc c $ \client -> f client
