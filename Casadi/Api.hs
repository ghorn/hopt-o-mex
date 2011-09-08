-- Api.hs

{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}

{-
this module is all the user should ever need to see. It is re-exported as Casadi.
In Casadi.* many functions have longer names to make maintaining the bindings easier, but these longer names
are either used to instance the Matrix typeclass or are given shorter names in this module.
-}

module Casadi.Api
       (
         SX(..)
       , SXMatrix(..)
       , DMatrix(..)
       , Matrix(..)
       , sxSymbolic
       , sxMatrixSymbolic
       , sxFunction
       , sxInt
       , sxDouble
       , gradient
       , hessian
       , jacobian
       ) where

import Casadi.SX
import Casadi.DMatrix
import Casadi.SXMatrix
import Casadi.SXFunction
import Casadi.Matrix
import System.IO.Unsafe(unsafePerformIO)

sxSymbolic :: String -> SX
{-# NOINLINE sxSymbolic #-}
sxSymbolic name = unsafePerformIO $ do
  sym <- sxCreateSymbolic name
  return sym

sxMatrixSymbolic :: String -> (Int,Int) -> SXMatrix
{-# NOINLINE sxMatrixSymbolic #-}
sxMatrixSymbolic prefix dim' = unsafePerformIO $ do
  mat <- sxMatrixCreateSymbolic prefix dim'
  return mat

sxFunction :: [SXMatrix] -> [SXMatrix] -> SXFunction
sxFunction = sxFunctionCreate

sxInt :: Int -> SX
sxInt = sxFromInt

sxDouble :: Double -> SX
sxDouble = sxFromDouble

--sxIntegral :: Integral a => a -> SX
--sxIntegral = sxFromIntegral
