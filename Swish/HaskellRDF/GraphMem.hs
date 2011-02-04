{-# LANGUAGE FlexibleInstances, MultiParamTypeClasses #-}
--------------------------------------------------------------------------------
--  See end of this file for licence information.
--------------------------------------------------------------------------------
-- |
--  Module      :  GraphMem
--  Copyright   :  (c) 2003, Graham Klyne, 2009 Vasili I Galchin, 2011 Douglas Burke
--  License     :  GPL V2
--
--  Maintainer  :  Graham Klyne
--  Stability   :  provisional
--  Portability :  H98
--
--  This module defines a simple memory-based graph instance.
--
--------------------------------------------------------------------------------

------------------------------------------------------------
-- Simple labelled directed graph value
------------------------------------------------------------

module Swish.HaskellRDF.GraphMem
    ( GraphMem(..)
    , setArcs, getArcs, add, delete, extract, labels
    , LabelMem(..)
    , labelIsVar, labelHash
      -- For debug/test:
    , matchGraphMem
    ) where

import Swish.HaskellRDF.GraphClass
import Swish.HaskellRDF.GraphMatch
import Swish.HaskellUtils.MiscHelpers
    ( hash )
import Swish.HaskellUtils.FunctorM
    ( FunctorM(..) )
import Control.Monad (liftM)
import Data.Ord (comparing)

-----------------------------------------------------
--  Memory-based graph type and graph class functions
-----------------------------------------------------

data GraphMem lb = GraphMem { arcs :: [Arc lb] }

instance (Label lb) => LDGraph GraphMem lb where
    getArcs      = arcs
    setArcs as g = g { arcs=as }
    -- gmap f g = g { arcs = (map $ fmap f) (arcs g) }
    containedIn = undefined -- TODO: what should this method do?

instance (Label lb) => Eq (GraphMem lb) where
    (==) = graphEq

instance (Label lb) => Show (GraphMem lb) where
    show = graphShow

instance Functor GraphMem where
    fmap f g = GraphMem $ map (fmap f) (arcs g)

instance FunctorM GraphMem where
    fmapM f g = GraphMem `liftM` mapM (fmapM f) (arcs g)

graphShow   :: (Label lb) => GraphMem lb -> String
graphShow g = "Graph:" ++ foldr ((++) . ("\n    " ++) . show) "" (arcs g)

{-
toGraph :: (Label lb) => [Arc lb] -> GraphMem lb
toGraph as = GraphMem { arcs=nub as }
-}

-----------
--  graphEq
-----------
--
--  Return Boolean graph equality

graphEq :: (Label lb) => GraphMem lb -> GraphMem lb -> Bool
graphEq g1 g2 = fst ( matchGraphMem g1 g2 )

-----------------
--  matchGraphMem
-----------------
--
--  GraphMem matching function accepting GraphMem value and returning
--  node map if successful
--
--  g1      is the first of two graphs to be compared
--  g2      is the second of two graphs to be compared
--
--  returns a label map that maps each label to an equivalence
--          class identifier, or Nothing if the graphs cannot be
--          matched.

matchGraphMem :: (Label lb) => GraphMem lb -> GraphMem lb
                            -> (Bool,LabelMap (ScopedLabel lb))
matchGraphMem g1 g2 =
    let
        gs1     = arcs g1
        gs2     = arcs g2
        matchable l1 l2
            | labelIsVar l1 && labelIsVar l2 = True
            | labelIsVar l1 || labelIsVar l2 = False
            | otherwise                      = l1 == l2
    in
        graphMatch matchable gs1 gs2

---------------
--  graphBiject
---------------
--
--  Return bijection between two graphs, or empty list
{-
graphBiject :: (Label lb) => GraphMem lb -> GraphMem lb -> [(lb,lb)]
graphBiject g1 g2 = if null lmap then [] else zip (sortedls g1) (sortedls g2)
    where
        lmap        = graphMatch g1 g2
        sortedls g  = map snd $
                      (sortBy indexComp) $
                      equivalenceClasses (graphLabels $ arcs g) lmap
        classComp ec1 ec2 = indexComp (classIndexVal ec1) (classIndexVal ec2)
        indexComp (g1,v1) (g2,v2)
            | g1 == g2  = compare v1 v2
            | otherwise = compare g1 g2
-}

------------------------------------------------------------
--  Minimal graph label value - for testing
------------------------------------------------------------

data LabelMem
    = LF String
    | LV String

instance Label LabelMem where
    labelIsVar (LV _)   = True
    labelIsVar _        = False
    getLocal   (LV loc) = loc
    getLocal   lab      = error "getLocal of non-variable label: " ++ show lab
    makeLabel           = LV 
    labelHash  seed lb  = hash seed (show lb)

instance Eq LabelMem where
    (LF l1) == (LF l2)  = l1 == l2
    (LV l1) == (LV l2)  = l1 == l2
    _ == _              = False

instance Show LabelMem where
    show (LF l1)        = '!' : l1
    show (LV l2)        = '?' : l2

instance Ord LabelMem where
    compare = comparing show 

--------------------------------------------------------------------------------
--
--  Copyright (c) 2003, Graham Klyne, 2009 Vasili I Galchin, 2011 Douglas Burke
--  All rights reserved.
--
--  This file is part of Swish.
--
--  Swish is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.
--
--  Swish is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with Swish; if not, write to:
--    The Free Software Foundation, Inc.,
--    59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
--
--------------------------------------------------------------------------------
