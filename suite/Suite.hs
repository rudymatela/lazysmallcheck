{-# LANGUAGE ExistentialQuantification, DeriveDataTypeable,
             DeriveFunctor, TypeFamilies #-}
{-# OPTIONS_GHC -ignore-dot-ghci #-}
import Control.Exception
import Control.Monad
import Data.Data
import Data.Typeable
import System.Exit

import Test.LazySmallCheck2012
import Test.LazySmallCheck2012.Core
import Test.LazySmallCheck2012.FunctionalValues

main = do mapM_ runTest suite
          putStrLn "\nSuite: Test suite complete."

runTest (Test str t v d) = do putStrLn $ "\n## Test '" ++ str ++ "': "
                              expect v $ mapM_ (`depthCheck` t) [0..d]

expect :: Bool -> IO () -> IO ()
expect True  = id
expect False = either (\(SomeException _) -> return ()) (const exitFailure) <=< try

data Test = forall a. (Data a, Typeable a, Testable a) => 
            Test String a Bool Depth

suite = [ test1, test2, test3, test4, test5, test6, test7, test8
        , test9, test10, test11a, test11b, test11c, test12a ]

------------------------------------------------------------------------------------

-- From Runciman, Naylor and Lindblad 2008

-- isPrefix
isPrefix :: [Int] -> [Int] -> Bool
isPrefix []     _  = True
isPrefix _      [] = False
isPrefix (x:xs) (y:ys) = x == y && isPrefix xs ys

test1 = Test "isPrefix" (\xs ys -> isPrefix xs (xs ++ ys)) True 5
test2 = Test "flip isPrefix" (\xs ys -> flip isPrefix xs (xs ++ ys)) False 5

-- Set insert
type Set a = [a]

insert :: Char -> [Char] -> [Char]
insert x []     = [x]
insert x (y:ys) | x <= y    = x:y:ys
                | otherwise = y : insert x ys
                              
ordered :: Ord a => [a] -> Bool
ordered (x:y:zs) = x <= y && ordered (y:zs)
ordered _ = True

test3 = Test "Set insert" (\c s -> ordered s ==> ordered (insert c s)) True 5

-- Associativity of Boolean
test4 = Test "Associativity of binary Boolean functions"
        (\f x y z -> let typ = f :: Bool -> Bool -> Bool
                     in f (f x y) z == f x (f y z)) False 5
        
-- isPrefix again
isPrefix_bad :: [Char] -> [Char] -> Bool
isPrefix_bad []     _  = True
isPrefix_bad _      [] = False
isPrefix_bad (x:xs) (y:ys) = x == y || isPrefix_bad xs ys

test5 = Test "isPrefix_bad with existential" 
        (\xs ys -> isPrefix_bad xs ys *==>* 
                   existsDeeperBy (+2) (\xs' -> (xs ++ xs') == ys))
        False 5
        
test6 = Test "isPrefix_bad with existential" 
        (\xs ys -> isPrefix xs ys *==>* 
                   existsDeeperBy (+2) (\xs' -> (xs ++ xs') == ys))
        True 4
                
------------------------------------------------------------------------------------

-- From Reich, Naylor and Runciman, 2012

-- Reductions to folds
test7 = Test "All reductions are folds"
        (\r -> let typ = r :: [Bool] -> Bool
               in existsDeeperBy (+2) $ 
                  \f z -> forAll $ \xs -> r xs == foldr f z xs)
        False 5

data Peano = Zero | Succ Peano 
           deriving (Data, Typeable, Eq, Ord, Show)

instance Serial Peano where
  series = cons0 Zero <|> cons1 Succ
instance Argument Peano where
  type Base Peano = Either () (BaseThunk Peano)
  toBase Zero     = Left ()
  toBase (Succ n) = Right (toBaseThunk n)
  fromBase (Left  _) = Zero
  fromBase (Right n) = Succ (fromBaseThunk n)

-- foldr1 f == foldl1 f

test8 = Test "foldr1 is the same as foldl1"
        (\f xs -> let typ = f :: Peano -> Peano -> Peano
                  in (not.null) xs ==> (foldr1 f xs == foldl1 f xs))
        False 5
        
----------------------------------------------------------------------

-- From Claessen and Hughes, 2000

-- (f . g) . h == f . (g . h)

test9 = Test "Associativity of assoc."
        (\f g h x -> let typ_f = f :: Peano -> Peano
                         typ_g = g :: Peano -> Peano
                         typ_h = h :: Peano -> Peano
                     in (f . (g . h)) x == ((f . g) . h) x)
        True 7
        
----------------------------------------------------------------------

-- From Claessen, 2012

-- Heaps are safe from fmaps

data Heap a = HEmpty | HNode a (Heap a) (Heap a) 
            deriving (Functor, Show, Data, Typeable)
                     
instance Serial a => Serial (Heap a) where 
  series = cons0 HEmpty <|> cons3 HNode

invariant :: Ord a => Heap a -> Bool
invariant HEmpty = True
invariant p@(HNode x _ _) = top x p
  where top x HEmpty = True
        top x (HNode y p q) = x <= y && top y p && top y q
        
test10 = Test "Any fmap over the heap maintains the invariant."
         (\h f -> invariant h *==>* 
                  invariant (fmap (f :: Peano -> Peano) h))
         False 5
         
-- Clock/Emit is a monad

data ClockEmit a = Step (ClockEmit a) 
                 | Emit a (ClockEmit a)
                 | Stop
                 deriving (Eq, Show, Data, Typeable)
                   
instance Serial a => Serial (ClockEmit a) where
  series = cons0 Stop <|> cons2 Emit <|> cons1 Step
  
(+++) :: ClockEmit a -> ClockEmit a -> ClockEmit a
Stop     +++ q        = q
p        +++ Stop     = p
Emit x p +++ q        = Emit x (p +++ q)
p        +++ Emit x q = Emit x (p +++ q)
Step p   +++ Step q    = Step (p +++ q)

instance Monad ClockEmit where
  return x     = Emit x Stop
  Stop     >>= k = Stop
  Step m   >>= k = Step (m >>= k)
  Emit x m >>= k = k x +++ (m >>= k)
  
test11a = Test "ClockBind obeys Return/Bind"
          (\x f -> let typ_f = f :: Bool -> ClockEmit Bool
                   in (return x >>= f) == f x)
          True 5
          
test11b = Test "ClockBind obeys Bind/Return"
          (\xs -> let typ_xs = xs :: ClockEmit Bool
                  in (xs >>= return) == xs)
          True 5
          
test11c = Test "ClockBind obeys Bind/Bind"
          (\xs f g -> let typ_xs = xs :: ClockEmit Bool
                          typ_f  = f  :: Bool -> ClockEmit Bool
                          typ_g  = g  :: Bool -> ClockEmit Bool
                      in (xs >>= (\x -> f x >>=g)) == ((xs >>= f) >>= g))
          False 5
          
----------------------------------------------------------------------

-- Contributed by Domonic Orchard at IFL 2012

-- Is Foo a comonad?

data Foo a = Foo a a a deriving (Show, Data, Typeable, Eq)

instance Serial a => Serial (Foo a) where
  series = cons3 Foo

instance Argument a => Argument (Foo a) where
  type Base (Foo a) = (BaseThunk a, (BaseThunk a, BaseThunk a))
  toBase (Foo x y z) = (toBaseThunk x, (toBaseThunk y, toBaseThunk z))
  fromBase (x, (y, z)) = Foo (fromBaseThunk x) (fromBaseThunk y) (fromBaseThunk z)
  
coreturn (Foo x _ _) = x
cobind f (Foo x y z) = Foo (f $ Foo x y z) (f $ Foo y x z) (f $ Foo z x y)

test12a = Test "Foo obeys Cobind/Coreturn"
          (\xs -> let typ_xs = xs :: Foo Bool
                  in cobind coreturn xs == xs)
          True 5