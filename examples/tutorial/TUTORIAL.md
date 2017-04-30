## Introduction to gRPC-Haskell

*This tutorial assumes that you already have a basic understanding of gRPC as well as Haskell.*

This will go through a basic example of using the library, with the `arithmetic` example in the `examples/arithmetic` directory. After cloning this repository, it would be a good idea to run `stack haddock` from within the repository directory to generate the documentation so you can read more about the functions and types we're using as we go. Also remember that [typed holes](https://wiki.haskell.org/GHC/Typed_holes) can be very handy.

The gRPC service we will be implementing provides two amazing functions:

1. `Add`, which adds two integers.
2. `RunningSum`, which receives a stream of integers from the client and finally returns a single integer that is the sum of all the integers it has received.

You can run the examples by running `stack exec arithmetic-server` and `stack exec arithmetic-client`.

### Library Organization

**tl;dr: you probably only need to import `Network.GRPC.HighLevel.Generated`.** Other modules are exposed for advanced users only.

This library exposes quite a few modules, but you won't need to worry about most of them. They are currently organized based on the level of abstraction they afford over using the C [gRPC Core library](http://www.grpc.io/grpc/core/) directly:

* *`Unsafe`* modules directly wrap functions in the gRPC Core library. Using them directly is like using C: you need to think about memory management, pointers, and so on. The rest of the library is built on top of these functions and users of gRPC-haskell should never need to deal with the `Unsafe` modules directly.
* *`LowLevel`* modules still require an understanding of the gRPC Core library, but guarantee memory and thread safety. Only advanced users with special requirements would use `LowLevel` modules directly.
* *`HighLevel`* modules give you an opinionated Haskell interface to gRPC that should cover most use cases while (hopefully) being easy to use. You should only need to import the `Network.GRPC.HighLevel.Generated` module to start using the library. If you need to import other modules, we probably forgot to re-export something and you should open an issue or PR.

### Getting started

To start out, we need to generate code for our protocol buffers and RPCs.

```
stack exec -- compile-proto-file --proto examples/echo/echo.proto > examples/echo/echo-hs/Echo.hs
```

The `.proto` file compiler always names the generated module the same as the `.proto` file, capitalizing the first letter if it is not already. Since our proto file is `arithmetic.proto`, the generated code should be placed in `Arithmetic.hs`.

The important things to notice in this generated file are:

1. For each proto message type, an equivalent Haskell type with the same name has been generated.
2. The `arithmeticServer` function takes a a record containing handlers for each RPC endpoint and some options, and starts a server. So, you just need to call this function to get a server running.
3, The `arithmeticClient` function takes a `Client` (which is just a proof that the gRPC core has been started) and gives you a record of functions that can be used to run RPCs.

### The server

First, we need to turn on some language extensions:

```
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
```

All we need to do to run a server is call the `arithmeticServer` function:

```
main :: IO ()
main = arithmeticServer handlers options
```

So we just need to define `handlers` and `options`.

`options` is easy-- it's just some basic options for the server. We can just use the default options for now, which will start the server listening on `localhost:50051`:

```
options :: ServiceOptions
options = defaultServiceOptions
```

`handlers` is a bit more involved. Its type is `Arithmetic ServerRequest ServerResponse`. Values of this type contain a record field for each RPC defined in your `.proto` file.

```
handlers :: Arithmetic ServerRequest ServerResponse
handlers = Arithmetic { arithmeticAdd = addHandler
                      , arithmeticRunningSum = runningSumHandler
                      }
```

You can think of the handlers as being of type `ServerRequest -> ServerResponse`, though there are a few more type parameters in there. The most important one is the first parameter, which specifies whether the RPC is streaming (`ClientStreaming`, `ServerStreaming`, or `BidiStreaming`) or not (`Normal`).

The `ServerRequest` passed to your handler contains all the tools you will need to handle the request, including:

1. The metadata the client sent with the request.
2. The protocol buffer message sent with the request, which has already been parsed into a Haskell type for you.
3. If it's a streaming request, you will also be given functions for sending or receiving messages in the stream.

#### The unary RPC handler for `Add`

So, let's pattern match on the `ServerRequest` for the `addHandler` function:

```
addHandler (ServerNormalRequest metadata (TwoInts x y)) = -- to be continued!
```

The body of the `addHandler` function just needs to add `x` and `y` and then bundle the answer up in a `ServerResponse`:

```
addHandler (ServerNormalRequest _metadata (TwoInts x y)) = do
  let answer = OneInt (x + y)
  return (ServerNormalResponse answer
                               [("metadata_key_one", "metadata_value")]
                               StatusOk
                               "addition is easy!")
```

Since this is a non-streaming "Normal" RPC, we use the the `ServerNormalResponse` constructor. Its parameters are the response message, some (optional) metadata key-value pairs, a status code, and a string with additional details about the status, which would normally be used to explain any errors in handling the request.

#### The client streaming handler for `RunningSum`

Now let's make our `runningSumHandler`. Since this is an RPC where the server reads from a stream of numbers, we pattern match on the `ServerReaderRequest` constructor:

```
runningSumHandler req@(ServerReaderRequest metadata recv) = -- to be continued!
```

Unlike the unary "Normal" request handler, we don't get a message from the client in this pattern match. Instead, we get an IO action `recv`, which we can run to wait for the client to send us another message.

There are three possibilities when we try to receive another message from the client:

1. The RPC breaks with some gRPC error, such as losing the connection with the client.
2. We receive another message from the client.
3. The client has sent its last message and is waiting for a response.

We write a simple loop that keeps track of the running sum and finally sends off a `ServerReaderResponse` when the client finishes streaming or an error occurs:

```
runningSumHandler req@(ServerReaderRequest metadata recv) =
  loop 0
    where loop !i =
            do msg <- recv
               case msg of
                 Left err -> return (ServerReaderResponse
                                      Nothing
                                      []
                                      StatusUnknown
                                      (fromString (show err)))
                 Right (Just (OneInt x)) -> loop (i + x)
                 Right Nothing -> return (ServerReaderResponse
                                           (Just (OneInt i))
                                           []
                                           StatusOk
                                           "")
```

The `ServerReaderResponse` type is almost the same as `ServerNormalResponse`, except that the first argument, the message to send back to the client, is optional. Otherwise, it takes metadata (which we leave empty), a status code, and a string containing more information about the status code.

### The client

The client-side code generated for us is `arithmeticClient`, which takes a `Client` as input and gives us a record containing actions that execute RPCs. To start up the C gRPC library and get a `Client`, we use `withGRPCClient`, which takes a `ClientConfig`:



```
clientConfig :: ClientConfig
clientConfig = ClientConfig { clientServerHost = "localhost"
                            , clientServerPort = 50051
                            , clientArgs = []
                            , clientSSLConfig = Nothing
                            }

main :: IO ()
main = withGRPCClient clientConfig $ \client -> do
  (Arithmetic arithmeticAdd arithmeticRunningSum) <- arithmeticClient client
  -- to be continued!
```

Now that we are on the client side, the `Arithmetic` record contains functions that make RPC requests. You can think of these functions as roughly having the type `ClientRequest -> ClientResult`. Like before, the particular constructors will vary depending on whether the RPC is streaming or not.

#### Requesting unary RPC

Here we construct a `ClientNormalRequest`, which takes as input a message, a timeout in seconds, and metadata. The result is a `ClientNormalResponse`, containing our the server's response, the initial and trailing metadata for the call, and the status and status details string.

```
-- Request for the Add RPC
  ClientNormalResponse (OneInt x) _meta1 _meta2 _status _details
    <- arithmeticAdd (ClientNormalRequest (TwoInts 2 2) 1 [])
  print ("2 + 2 = " ++ (show x))
```

#### Executing a client streaming RPC

Doing a streaming request is slightly trickier. As input to the streaming RPC action, we pass in another IO action that tells `grpc-haskell` what to send. It takes a `send` action as input. This is a bit convoluted, but it guarantees that you can't send streaming messages outside of the context of a streaming call!

```
-- Request for the RunningSum RPC
ClientWriterResponse reply _streamMeta1 _streamMeta2 streamStatus streamDtls
  <- arithmeticRunningSum $ ClientWriterRequest 1 [] $ \send -> do
      _ <- send (OneInt 1)
      _ <- send (OneInt 2)
      _ <- send (OneInt 3)
      return ()
```

Each `send` potentially returns an error message, but for the purposes of this tutorial, we skip the error checking and throw away the result.