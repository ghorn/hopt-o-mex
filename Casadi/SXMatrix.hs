-- SXMatrix.hs

{-# OPTIONS_GHC -Wall #-}
--{-# OPTIONS_GHC -Wall -fno-cse -fno-full-laziness #-}
{-# LANGUAGE ForeignFunctionInterface, MultiParamTypeClasses #-}

module Casadi.SXMatrix
       (
         SXMatrix(..)
       , SXMatrixRaw(..)
       , sxMatrixCreateSymbolic
       , sxMatrixNewZeros
       , gradient
       , hessian
       , jacobian
       ) where

import Casadi.SX
import Casadi.SXFunctionRaw
import Casadi.CasadiInterfaceUtils
import Casadi.Matrix

import Foreign.C
import Foreign.ForeignPtr
import Foreign.Ptr
import Control.Exception(mask_)
import System.IO.Unsafe(unsafePerformIO)
import Control.DeepSeq

-- the SXMatrix data type
data SXMatrixRaw = SXMatrixRaw
newtype SXMatrix = SXMatrix (ForeignPtr SXMatrixRaw)

instance NFData SXMatrix where
  rnf x = x `seq` ()

-- foreign imports
foreign import ccall unsafe "sxMatrixCreateSymbolic" c_sxMatrixCreateSymbolic
  :: Ptr CChar -> CInt -> CInt -> IO (Ptr SXMatrixRaw)
foreign import ccall unsafe "sxMatrixDuplicate" c_sxMatrixDuplicate
  :: (Ptr SXMatrixRaw) -> IO (Ptr SXMatrixRaw)
foreign import ccall unsafe "&sxMatrixDelete" c_sxMatrixDelete
  :: FunPtr (Ptr SXMatrixRaw -> IO ())
foreign import ccall unsafe "sxMatrixZeros" c_sxMatrixZeros
  :: CInt -> CInt -> IO (Ptr SXMatrixRaw)
foreign import ccall unsafe "sxMatrixShow" c_sxMatrixShow
  :: Ptr CChar -> CInt -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMatrixAt" c_sxMatrixAt
  :: (Ptr SXMatrixRaw) -> CInt -> CInt -> (Ptr SXRaw) -> IO ()
foreign import ccall unsafe "sxMatrixSet" c_sxMatrixSet
  :: (Ptr SXRaw) -> CInt -> CInt -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMatrixSize1" c_sxMatrixSize1
  :: (Ptr SXMatrixRaw) -> IO CInt
foreign import ccall unsafe "sxMatrixSize2" c_sxMatrixSize2
  :: (Ptr SXMatrixRaw) -> IO CInt
foreign import ccall unsafe "sxMatrixPlus" c_sxMatrixPlus
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMatrixMinus" c_sxMatrixMinus
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMatrixNegate" c_sxMatrixNegate
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMM" c_sxMM
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMatrixTranspose" c_sxMatrixTranspose
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMatrixIsEqual" c_sxMatrixIsEqual
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO CInt
foreign import ccall unsafe "sxMatrixScale" c_sxMatrixScale
  :: (Ptr SXRaw) -> (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "sxMatrixInv" c_sxMatrixInv
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()

foreign import ccall unsafe "myGradient" c_myGradient
  :: (Ptr SXRaw) -> (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "myHessian" c_myHessian
  :: (Ptr SXRaw) -> (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()
foreign import ccall unsafe "myJacobian" c_myJacobian
  :: (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> (Ptr SXMatrixRaw) -> IO ()

foreign import ccall unsafe "sxFunctionEvaluateSXMatrix" c_sxFunctionEvaluateSXMatrix
  :: CInt -> Ptr (Ptr SXMatrixRaw) -> CInt -> Ptr (Ptr SXMatrixRaw) -> Ptr SXFunctionRaw -> IO ()

----------------- create -------------------------
sxMatrixCreateSymbolic :: String -> (Int, Int) -> IO SXMatrix
sxMatrixCreateSymbolic prefix (n,m) = mask_ $ do
  cPrefix <- newCString prefix
  mat <- c_sxMatrixCreateSymbolic cPrefix (fromIntegral n) (fromIntegral m) >>= newForeignPtr c_sxMatrixDelete
  return $ SXMatrix mat


sxMatrixDuplicate :: SXMatrix -> IO SXMatrix
sxMatrixDuplicate (SXMatrix old) = mask_ $ do
  new <- withForeignPtr old c_sxMatrixDuplicate >>= newForeignPtr c_sxMatrixDelete
  return $ SXMatrix new


sxMatrixNewZeros :: (Int, Int) -> IO SXMatrix
sxMatrixNewZeros (n,m) = mask_ $ do
  let n' = safeToCInt n
      m' = safeToCInt m
      
      safeToCInt :: Int -> CInt
      safeToCInt x
        | and [toInteger x <= maxCInt, toInteger x >= minCInt] = fromIntegral x
        | otherwise = error "Error - sxMatrixNewZeros dimensions too big"
        where
          maxCInt = fromIntegral (maxBound :: CInt)
          minCInt = fromIntegral (minBound :: CInt)

  mat <- c_sxMatrixZeros n' m' >>= newForeignPtr c_sxMatrixDelete
  return $ SXMatrix mat


sxMatrixZeros :: (Int,Int) -> SXMatrix
{-# NOINLINE sxMatrixZeros #-}
sxMatrixZeros dim = unsafePerformIO $ do
  mat <- sxMatrixNewZeros dim
  return mat


sxMatrixFromList :: [SX] -> SXMatrix
{-# NOINLINE sxMatrixFromList #-}
sxMatrixFromList sxList = unsafePerformIO $ do
  m0 <- sxMatrixNewZeros (length sxList, 1)
  let indexedSXList = zip sxList $ take (length sxList) [0..]
  return $ foldl (\acc (sx,idx) -> sxMatrixSet acc (idx,0) sx) m0 indexedSXList


---------------- show -------------------
sxMatrixShow :: SXMatrix -> String
{-# NOINLINE sxMatrixShow #-}
sxMatrixShow (SXMatrix s) = unsafePerformIO $ do
  (stringRef, stringLength) <- newCStringLen $ replicate 4096 ' '
  withForeignPtr s $ c_sxMatrixShow stringRef (fromIntegral stringLength)
  peekCString stringRef


--------------- getters/setters ---------------------
sxMatrixAt :: SXMatrix -> (Int,Int) -> IO SX
sxMatrixAt (SXMatrix matIn) (n,m) = do
  SX sxOut <- sxNewInt 0
  withForeignPtrs2 (\matIn' sxOut' -> c_sxMatrixAt matIn' (fromIntegral n) (fromIntegral m) sxOut') matIn sxOut
  return (SX sxOut)

sxMatrixSet :: SXMatrix -> (Int,Int) -> SX -> SXMatrix
{-# NOINLINE sxMatrixSet #-}
sxMatrixSet (SXMatrix matIn) (n,m) (SX val) = unsafePerformIO $ do
  SXMatrix matOut <- sxMatrixDuplicate (SXMatrix matIn)
  let n' = fromIntegral n
      m' = fromIntegral m
  withForeignPtrs2 (\val' matOut' -> c_sxMatrixSet val' n' m' matOut') val matOut
  return (SXMatrix matOut)


---------------- dimensions --------------------
sxMatrixSize :: SXMatrix -> (Int,Int)
{-# NOINLINE sxMatrixSize #-}
sxMatrixSize (SXMatrix matIn) = unsafePerformIO $ do
  n <- withForeignPtr matIn c_sxMatrixSize1
  m <- withForeignPtr matIn c_sxMatrixSize2
  return (fromIntegral n, fromIntegral m)


sxMatrixToLists :: SXMatrix -> [[SX]]
{-# NOINLINE sxMatrixToLists #-}
sxMatrixToLists mat = unsafePerformIO $ do
  let f row = mapM (\col -> sxMatrixAt mat (row, col)) [0..m-1]
      (n,m) = sxMatrixSize mat
  mapM f [0..n-1]


-- turns n by 1 matrix into a list of SX, returns error if matrix is not n by 1
sxMatrixToList :: SXMatrix -> [SX]
{-# NOINLINE sxMatrixToList #-}
sxMatrixToList mat = unsafePerformIO $ do
  let (n,m) = sxMatrixSize mat
  if m == 1
    then mapM (\row -> sxMatrixAt mat (row, 0)) [0..n-1]
    else error "sxMatrixToList can only be used on an n by 1 matrix"


------------------------- math ---------------------------------
sxMatrixPlus :: SXMatrix -> SXMatrix -> SXMatrix
{-# NOINLINE sxMatrixPlus #-}
sxMatrixPlus (SXMatrix m0) (SXMatrix m1) = unsafePerformIO $ do
  let size'
        | sizeM0 == sizeM1 = sizeM0
        | otherwise      = error "sxMatrixPlus can't add matrices of different dimensions"
        where
          sizeM0 = sxMatrixSize (SXMatrix m0)
          sizeM1 = sxMatrixSize (SXMatrix m1)
  SXMatrix mOut <- sxMatrixNewZeros size'
  withForeignPtrs3 c_sxMatrixPlus m0 m1 mOut
  return $ SXMatrix mOut


sxMatrixMinus :: SXMatrix -> SXMatrix -> SXMatrix
{-# NOINLINE sxMatrixMinus #-}
sxMatrixMinus (SXMatrix m0) (SXMatrix m1) = unsafePerformIO $ do
  let size'
        | sizeM0 == sizeM1 = sizeM0
        | otherwise      = error "sxMatrixMinus can't add matrices of different dimensions"
        where
          sizeM0 = sxMatrixSize (SXMatrix m0)
          sizeM1 = sxMatrixSize (SXMatrix m1)
  SXMatrix mOut <- sxMatrixNewZeros size'
  withForeignPtrs3 c_sxMatrixMinus m0 m1 mOut
  return $ SXMatrix mOut


sxMatrixNegate :: SXMatrix -> SXMatrix
{-# NOINLINE sxMatrixNegate #-}
sxMatrixNegate (SXMatrix m0) = unsafePerformIO $ do
  SXMatrix mOut <- sxMatrixNewZeros (sxMatrixSize (SXMatrix m0))
  withForeignPtrs2 c_sxMatrixNegate m0 mOut
  return $ SXMatrix mOut


sxMM :: SXMatrix -> SXMatrix -> SXMatrix
{-# NOINLINE sxMM #-}
sxMM (SXMatrix m0) (SXMatrix m1) = unsafePerformIO $ do
  let size'
        | colsM0 == rowsM1 = (rowsM0, colsM1)
        | otherwise        = error $ "sxMM can't multiply " ++ (show (size (SXMatrix m0))) ++ " matrix by " ++ (show (size (SXMatrix m1))) ++ " matrix"
        where
          (rowsM0, colsM0) = sxMatrixSize (SXMatrix m0)
          (rowsM1, colsM1) = sxMatrixSize (SXMatrix m1)

  SXMatrix mOut <- sxMatrixNewZeros size'
  withForeignPtrs3 c_sxMM m0 m1 mOut
  return $ SXMatrix mOut


sxMatrixTranspose :: SXMatrix -> SXMatrix
{-# NOINLINE sxMatrixTranspose #-}
sxMatrixTranspose (SXMatrix mIn) = unsafePerformIO $ do
  SXMatrix mOut <- sxMatrixNewZeros $ sxMatrixSize (SXMatrix mIn)
  withForeignPtrs2 c_sxMatrixTranspose mIn mOut
  return $ SXMatrix mOut


sxMatrixIsEqual :: SXMatrix -> SXMatrix -> Bool
{-# NOINLINE sxMatrixIsEqual #-}
sxMatrixIsEqual (SXMatrix m0) (SXMatrix m1) = unsafePerformIO $ do
  isEq <- withForeignPtrs2 c_sxMatrixIsEqual m0 m1
  if (isEq == 1)
    then
    return True
    else
    return False


sxMatrixScale :: SX -> SXMatrix -> SXMatrix
{-# NOINLINE sxMatrixScale #-}
sxMatrixScale (SX scalar) (SXMatrix mIn) = unsafePerformIO $ do
  SXMatrix mOut <- sxMatrixNewZeros (1,1)
  withForeignPtrs3 c_sxMatrixScale scalar mIn mOut
  return $ SXMatrix mOut


sxMatrixInv :: SXMatrix -> SXMatrix
{-# NOINLINE sxMatrixInv #-}
sxMatrixInv (SXMatrix mIn) = unsafePerformIO $ do
  SXMatrix mOut <- sxMatrixNewZeros (1,1)
  withForeignPtrs2 c_sxMatrixInv mIn mOut
  return $ SXMatrix mOut


sxMatrixFromIntegral :: Integral a => a -> SXMatrix
{-# NOINLINE sxMatrixFromIntegral #-}
sxMatrixFromIntegral i = unsafePerformIO $ do
  s <- sxNewIntegral i
  return $ sxMatrixFromList [s]


----------------- ad -----------------------
gradient :: SXMatrix -> SXMatrix -> SXMatrix
{-# NOINLINE gradient #-}
gradient expr (SXMatrix argsRaw) = unsafePerformIO $ do
  if (1,1) /= size expr
    then do error $ "error: can't take gradient of non-scalar, dimensions: " ++ show (size expr)
    else do let [(SX expRaw)] = toList expr
            SXMatrix mOut <- sxMatrixNewZeros (1,1)
            withForeignPtrs3 c_myGradient expRaw argsRaw mOut
            return $ (SXMatrix mOut)

hessian :: SXMatrix -> SXMatrix -> SXMatrix
{-# NOINLINE hessian #-}
hessian expr (SXMatrix argsRaw) = unsafePerformIO $ do
  if (1,1) /= size expr
    then do error $ "error: can't take hessian of non-scalar, dimensions: " ++ show (size expr)
    else do let [(SX expRaw)] = toList expr
            SXMatrix mOut <- sxMatrixNewZeros (1,1)
            withForeignPtrs3 c_myHessian expRaw argsRaw mOut
            return $ (SXMatrix mOut)

jacobian :: SXMatrix -> SXMatrix -> SXMatrix
{-# NOINLINE jacobian #-}
jacobian (SXMatrix expRaw) (SXMatrix argsRaw) = unsafePerformIO $ do
  SXMatrix mOut <- sxMatrixNewZeros (1,1)
  withForeignPtrs3 c_myJacobian expRaw argsRaw mOut
  return $ (SXMatrix mOut)


----------------- typeclass stuff ------------------
instance Show SXMatrix where
  show m = f (sxMatrixSize m)
    where
      f (1,1) = "[[" ++ (sxMatrixShow m) ++ "]]"
      f (_,1) = sxMatrixShow m
      f (1,_) = init $ sxMatrixShow m
      f (_,_) = init $ sxMatrixShow m


instance Eq SXMatrix where
  (==) = sxMatrixIsEqual
  (/=) sx0 sx1 = not $ sx0 == sx1


instance Num SXMatrix where
  (+) = sxMatrixPlus
  (-) = sxMatrixMinus
  (*) m0 m1
    | sxMatrixSize m0 == (1,1) = sxMatrixScale s0 m1
    | sxMatrixSize m1 == (1,1) = sxMatrixScale s1 m0
    | otherwise                = sxMM m0 m1
      where
        [s0] = sxMatrixToList m0
        [s1] = sxMatrixToList m1

  abs = error "abs not defined for instance Num SXMatrix"
  signum = error "signum not defined for instance Num SXMatrix"

  fromInteger = sxMatrixFromIntegral

  negate = sxMatrixNegate


instance Fractional SXMatrix where
  (/) m0 m1 = m0 * (recip m1)
  recip mat = sxMatrixInv mat
  fromRational x = sxMatrixFromList [fromRational x :: SX]


instance Matrix SXMatrix SX SXMatrixRaw where
  trans = sxMatrixTranspose
  size = sxMatrixSize
  rows = fst . sxMatrixSize
  cols = snd . sxMatrixSize
  toList = sxMatrixToList
  toLists = sxMatrixToLists
  fromList = sxMatrixFromList
  fromLists = error "sxMatrixFromLists not yet implemented"
  vertcat mats = fromList $ concat $ map toList mats
  inv = sxMatrixInv
  scale = sxMatrixScale
  zeros = sxMatrixZeros
  
  c_sxFunctionEvaluate _ = c_sxFunctionEvaluateSXMatrix
  getForeignPtr (SXMatrix r) = r
  newZeros = sxMatrixNewZeros

instance Boundable SXMatrix where
  bound xs (lbs, ubs) = fromList $ zipWith bound (toList xs) (zip (toList lbs) (toList ubs))
      
