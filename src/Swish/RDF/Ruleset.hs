{-# LANGUAGE MultiParamTypeClasses #-}
--------------------------------------------------------------------------------
--  See end of this file for licence information.
--------------------------------------------------------------------------------
-- |
--  Module      :  Ruleset
--  Copyright   :  (c) 2003, Graham Klyne, 2009 Vasili I Galchin, 2011, 2012 Douglas Burke
--  License     :  GPL V2
--
--  Maintainer  :  Douglas Burke
--  Stability   :  experimental
--  Portability :  MultiParamTypeClasses
--
--  This module defines a ruleset data type, used to collect information
--  about a ruleset that may contribute torwards inferences in RDF;
--  e.g. RDF and RDFS are rulesets.
--
--  A ruleset consists of a namespace, a collection of axioms, and
--  a collection of rules.
--
--------------------------------------------------------------------------------

module Swish.RDF.Ruleset
    ( Ruleset(..), RulesetMap
    , makeRuleset, getRulesetNamespace, getRulesetAxioms, getRulesetRules
    , getRulesetAxiom, getRulesetRule
    , getContextAxiom, getMaybeContextAxiom
    , getContextRule,  getMaybeContextRule
    )
where

import Swish.Utils.Namespace (Namespace, ScopedName)
import Swish.RDF.Rule (Formula(..), Rule(..))

import Swish.Utils.LookupMap
    ( LookupEntryClass(..), LookupMap(..)
    , mapFindMaybe
    )

{-
Used for the Show instance of Ruleset, which was
used for debugging but has been removed as not
really needed by the general user.

import Swish.Utils.ShowM (ShowM(..))
import Data.List (intercalate)
-}

import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)

-- | A Rule set.

data Ruleset ex = Ruleset
    { rsNamespace :: Namespace    -- ^ Namespace.
    , rsAxioms    :: [Formula ex] -- ^ Axioms.
    , rsRules     :: [Rule ex]    -- ^ Rules.
    }

{-

Used for debugging.

instance (ShowM ex) => Show (Ruleset ex) where
  show (Ruleset ns axs rls) = 
    intercalate "\n" 
    [ "Ruleset: " ++ show ns
    , "Axioms:" ]
    ++ (showsFormulae "\n" axs 
       (intercalate "\n" ("Rules:" : map show rls))) ""
-}

-- | Ruleset comparisons are based only on their namespace components.
instance Eq (Ruleset ex) where
    r1 == r2 = rsNamespace r1 == rsNamespace r2

instance LookupEntryClass (Ruleset ex) Namespace (Ruleset ex)
    where
        keyVal   r@(Ruleset k _ _) = (k,r)
        newEntry (_,r)             = r

-- | A 'LookupMap' for a 'Ruleset'.
type RulesetMap ex = LookupMap (Ruleset ex)

-- | Create a ruleset.
makeRuleset :: Namespace -> [Formula ex] -> [Rule ex] -> Ruleset ex
makeRuleset nsp fms rls = Ruleset
    { rsNamespace = nsp
    , rsAxioms    = fms
    , rsRules     = rls
    }

-- | Extract the namespace of a ruleset.
getRulesetNamespace :: Ruleset ex -> Namespace
getRulesetNamespace = rsNamespace

-- | Extract the axioms from a ruleset.
getRulesetAxioms :: Ruleset ex -> [Formula ex]
getRulesetAxioms = rsAxioms

-- | Extract the rules from a ruleset.
getRulesetRules :: Ruleset ex -> [Rule ex]
getRulesetRules = rsRules

-- | Find a named axiom in a ruleset.
getRulesetAxiom :: ScopedName -> Ruleset ex -> Maybe (Formula ex)
getRulesetAxiom nam rset =
    mapFindMaybe nam (LookupMap (getRulesetAxioms rset))
    -- listToMaybe $ filter ( (matchName nam) . formName ) $ getRulesetAxioms rset

-- | Find a named rule in a ruleset. 
getRulesetRule :: ScopedName -> Ruleset ex -> Maybe (Rule ex)
getRulesetRule nam rset =
    mapFindMaybe nam (LookupMap (getRulesetRules rset))
    -- listToMaybe $ filter ( (matchName nam) . ruleName ) $ getRulesetRules rset

-- | Find a named axiom in a proof context.
getContextAxiom :: 
  ScopedName -- ^ Name of axiom.
  -> Formula ex -- ^ Default axiom (used if named component does not exist).
  -> [Ruleset ex] -- ^ Rulesets to search.
  -> Formula ex
getContextAxiom nam def rsets = fromMaybe def (getMaybeContextAxiom nam rsets)
    {-
    foldr (flip fromMaybe) def $ map (getRulesetAxiom nam) rsets
    -}

-- | Find a named axiom in a proof context.
getMaybeContextAxiom ::
  ScopedName -- ^ Name of axiom.
  -> [Ruleset ex] -- ^ Rulesets to search.
  -> Maybe (Formula ex)
getMaybeContextAxiom nam rsets =
    listToMaybe $ mapMaybe (getRulesetAxiom nam) rsets

-- | Find a named rule in a proof context.
getContextRule :: 
  ScopedName -- ^ Name of rule.
  -> Rule ex -- ^ Default rule (used if named component does not exist).
  -> [Ruleset ex] -- ^ Rulesets to search.
  -> Rule ex
getContextRule nam def rsets = fromMaybe def (getMaybeContextRule nam rsets)
    {-
    foldr (flip fromMaybe) def $ map (getRulesetRule nam) rsets
    -}

-- | Find a named rule in a proof context.
getMaybeContextRule :: 
  ScopedName -- ^ Name of rule.
  -> [Ruleset ex] -- ^ Rulesets to search.
  -> Maybe (Rule ex)
getMaybeContextRule nam rsets =
    listToMaybe $ mapMaybe (getRulesetRule nam) rsets

--------------------------------------------------------------------------------
--
--  Copyright (c) 2003, Graham Klyne, 2009 Vasili I Galchin,
--    2011, 2012 Douglas Burke
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
