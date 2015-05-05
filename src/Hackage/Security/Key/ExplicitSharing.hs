module Hackage.Security.Key.ExplicitSharing (
    -- * Reading
    DeserializationError(..)
  , ReadJSON -- opaque
  , runReadJSON
    -- ** Primitive operations
  , validate
  , addKeys
  , withKeys
  , readKeyAsId
    -- ** Utility
  , parseJSON
  , readCanonical
    -- * Writing
  , writeKeyAsId
  , renderJSON
  , writeCanonical
  ) where

import Control.Exception
import Control.Monad.Except
import Control.Monad.Reader
import Data.Typeable (Typeable)
import qualified Data.ByteString.Lazy as BS.L

import Hackage.Security.Key
import Hackage.Security.Key.Env (KeyEnv)
import Hackage.Security.JSON
import Hackage.Security.Some
import Text.JSON.Canonical
import qualified Hackage.Security.Key.Env as KeyEnv

{-------------------------------------------------------------------------------
  Reading
-------------------------------------------------------------------------------}

data DeserializationError =
    -- | Malformed JSON has syntax errors in the JSON itself
    -- (i.e., we cannot even parse it to a JSValue)
    DeserializationErrorMalformed String

    -- | Invalid JSON has valid syntax but invalid structure
    --
    -- The string gives a hint about what we expected instead
  | DeserializationErrorSchema String

    -- | The JSON file contains a key ID of an unknown key
  | DeserializationErrorUnknownKey KeyId

    -- | Some verification step failed
  | DeserializationErrorValidation String
  deriving (Typeable, Show)

instance Exception DeserializationError

-- We intentially do not export the MonadReader instance
newtype ReadJSON a = ReadJSON {
    unReadJSON :: ExceptT DeserializationError (Reader KeyEnv) a
  }
  deriving (Functor, Applicative, Monad, MonadError DeserializationError)

instance ReportSchemaErrors ReadJSON where
  expected str = throwError $ DeserializationErrorSchema $ "Expected " ++ str

runReadJSON :: KeyEnv -> ReadJSON a -> Either DeserializationError a
runReadJSON env act = runReader (runExceptT (unReadJSON act)) env

{-------------------------------------------------------------------------------
  Reading: Primitive operations
-------------------------------------------------------------------------------}

validate :: String -> Bool -> ReadJSON ()
validate _   True  = return ()
validate msg False = throwError $ DeserializationErrorValidation msg

addKeys :: KeyEnv -> ReadJSON a -> ReadJSON a
addKeys keys (ReadJSON act) = ReadJSON $ local (KeyEnv.union keys) act

withKeys :: KeyEnv -> ReadJSON a -> ReadJSON a
withKeys keys (ReadJSON act) = ReadJSON $ local (const keys) act

readKeyAsId :: JSValue -> ReadJSON (Some PublicKey)
readKeyAsId (JSString kId) = lookupKey (KeyId kId)
readKeyAsId _ = expected "key ID"

lookupKey :: KeyId -> ReadJSON (Some PublicKey)
lookupKey kId = do
    env <- ReadJSON $ ask
    case KeyEnv.lookup kId env of
      Just key -> return key
      Nothing  -> throwError $ DeserializationErrorUnknownKey kId

{-------------------------------------------------------------------------------
  Reading: Utility
-------------------------------------------------------------------------------}

parseJSON :: FromJSON ReadJSON a
          => KeyEnv
          -> BS.L.ByteString
          -> Either DeserializationError a
parseJSON env bs =
    case parseCanonicalJSON bs of
      Left  err -> Left (DeserializationErrorMalformed err)
      Right val -> runReadJSON env (fromJSON val)

readCanonical :: FromJSON ReadJSON a
              => KeyEnv
              -> FilePath
              -> IO (Either DeserializationError a)
readCanonical env fp = parseJSON env <$> BS.L.readFile fp

{-------------------------------------------------------------------------------
  Writing: Primitive functions
-------------------------------------------------------------------------------}

writeKeyAsId :: Some PublicKey -> JSValue
writeKeyAsId = JSString . keyIdString . someKeyId

{-------------------------------------------------------------------------------
  Writing: Utility
-------------------------------------------------------------------------------}

renderJSON :: ToJSON a => a -> BS.L.ByteString
renderJSON = renderCanonicalJSON . toJSON

writeCanonical :: ToJSON a => FilePath -> a -> IO ()
writeCanonical fp = BS.L.writeFile fp . renderJSON
