{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

--------------------------------------------------------------------------------
--  See end of this file for licence information.
--------------------------------------------------------------------------------
-- |
--  Module      :  Internal
--  Copyright   :  (c) 2003, Graham Klyne, 2009 Vasili I Galchin,
--                 2011, 2012 Douglas Burke
--  License     :  GPL V2
--
--  Maintainer  :  Douglas Burke
--  Stability   :  experimental
--  Portability :  CPP, OverloadedStrings
--
--  Utility routines.
--
--------------------------------------------------------------------------------

module Swish.RDF.Formatter.Internal
    ( NodeGenLookupMap
    , SubjTree
    , PredTree
    , LabelContext(..)
    , NodeGenState(..)
    , emptyNgs 
    , findMaxBnode
    , getCollection
    , processArcs
    , findPrefix
      -- N3-like formatting
    , quoteB
    , quoteText
    , showScopedName
    , formatScopedName
    , formatPrefixLines
    , maybeExtractList
    , formatPlainLit
    , formatLangLit
    , formatTypedLit
    )
where

import Swish.GraphClass (Arc(..), ArcSet)
import Swish.Namespace (ScopedName, getScopeLocal, getScopeURI)
import Swish.QName (getLName)

import Swish.RDF.Graph (RDFGraph, RDFLabel(..), NamespaceMap)
import Swish.RDF.Graph (labels, getArcs, resRdfFirst, resRdfRest, resRdfNil
                       , quote
                       , quoteT
                       )
import Swish.RDF.Vocabulary (LanguageTag, fromLangTag, xsdBoolean, xsdDecimal, xsdInteger, xsdDouble)

import Data.List (delete, foldl', groupBy)
import Data.Monoid (mconcat)
import Data.Word

import Network.URI (URI)
import Network.URI.Ord ()

import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.Lazy.Builder as B

#if defined(__GLASGOW_HASKELL__) && (__GLASGOW_HASKELL__ >= 701)
import Data.Tuple (swap)
#else
swap :: (a,b) -> (b,a)
swap (a,b) = (b,a)
#endif

findPrefix :: URI -> M.Map a URI -> Maybe a
findPrefix u = M.lookup u . M.fromList . map swap . M.assocs

-- | Node name generation state information that carries through
--  and is updated by nested formulae.
type NodeGenLookupMap = M.Map RDFLabel Word32

type SubjTree lb = [(lb,PredTree lb)]
type PredTree lb = [(lb,[lb])]

-- simple context for label creation
-- (may be a temporary solution to the problem
--  of label creation)
--
data LabelContext = SubjContext | PredContext | ObjContext
                    deriving (Eq, Show)

data NodeGenState = Ngs
    { prefixes  :: NamespaceMap
    , nodeMap   :: NodeGenLookupMap
    , nodeGen   :: Word32
    }

emptyNgs :: NodeGenState
emptyNgs = Ngs
    { prefixes  = M.empty
    , nodeMap   = M.empty
    , nodeGen   = 0
    }

{-|
Removes the first occurrence of the item from the
association list, returning it's contents and the rest
of the list, if it exists.
-}
removeItem :: (Eq a) => [(a,b)] -> a -> Maybe (b, [(a,b)])
removeItem os x =
  let (as, bs) = break (\a -> fst a == x) os
  in case bs of
    ((_,b):bbs) -> Just (b, as ++ bbs)
    [] -> Nothing

{-|
Given a set of statements and a label, return the details of the
RDF collection referred to by label, or Nothing.

For label to be considered as representing a collection we require the
following conditions to hold (this is only to support the
serialisation using the '(..)' syntax and does not make any statement
about semantics of the statements with regard to RDF Collections):

  - there must be one rdf_first and one rdfRest statement
  - there must be no other predicates for the label

-} 
getCollection ::          
  SubjTree RDFLabel -- ^ statements organized by subject
  -> RDFLabel -- ^ does this label represent a list?
  -> Maybe (SubjTree RDFLabel, [RDFLabel], [RDFLabel])
     -- ^ the statements with the elements removed; the
     -- content elements of the collection (the objects of the rdf:first
     -- predicate) and the nodes that represent the spine of the
     -- collection (in reverse order, unlike the actual contents which are in
     -- order).
getCollection subjList lbl = go subjList lbl ([],[]) 
    where
      go sl l (cs,ss) | l == resRdfNil = Just (sl, reverse cs, ss)
                      | otherwise = do
        (pList1, sl') <- removeItem sl l
        ([pFirst], pList2) <- removeItem pList1 resRdfFirst
        ([pNext], []) <- removeItem pList2 resRdfRest

        go sl' pNext (pFirst : cs, l : ss)

----------------------------------------------------------------------
--  Graph-related helper functions
----------------------------------------------------------------------

processArcs :: RDFGraph -> (SubjTree RDFLabel, [RDFLabel])
processArcs gr =
    let arcs = sortArcs $ getArcs gr
    in (arcTree arcs, countBnodes arcs)

newtype SortedArcs lb = SA [Arc lb]

sortArcs :: (Ord lb) => ArcSet lb -> SortedArcs lb
sortArcs = SA . S.toAscList

--  Rearrange a list of arcs into a tree of pairs which group together
--  all statements for a single subject, and similarly for multiple
--  objects of a common predicate.
--
arcTree :: (Eq lb) => SortedArcs lb -> SubjTree lb
arcTree (SA as) = commonFstEq (commonFstEq id) $ map spopair as
    where
        spopair (Arc s p o) = (s,(p,o))

{-
arcTree as = map spopair $ sort as
    where
        spopair (Arc s p o) = (s,[(p,[o])])
-}

--  Rearrange a list of pairs so that multiple occurrences of the first
--  are commoned up, and the supplied function is applied to each sublist
--  with common first elements to obtain the corresponding second value
commonFstEq :: (Eq a) => ( [b] -> c ) -> [(a,b)] -> [(a,c)]
commonFstEq f ps =
    [ (fst $ head sps,f $ map snd sps) | sps <- groupBy fstEq ps ]
    where
        fstEq (f1,_) (f2,_) = f1 == f2

{-
-- Diagnostic code for checking arcTree logic:
testArcTree = (arcTree testArcTree1) == testArcTree2
testArcTree1 =
    [Arc "s1" "p11" "o111", Arc "s1" "p11" "o112"
    ,Arc "s1" "p12" "o121", Arc "s1" "p12" "o122"
    ,Arc "s2" "p21" "o211", Arc "s2" "p21" "o212"
    ,Arc "s2" "p22" "o221", Arc "s2" "p22" "o222"
    ]
testArcTree2 =
    [("s1",[("p11",["o111","o112"]),("p12",["o121","o122"])])
    ,("s2",[("p21",["o211","o212"]),("p22",["o221","o222"])])
    ]
-}


findMaxBnode :: RDFGraph -> Word32
findMaxBnode = S.findMax . S.map getAutoBnodeIndex . labels

getAutoBnodeIndex   :: RDFLabel -> Word32
getAutoBnodeIndex (Blank ('_':lns)) = res where
    -- cf. prelude definition of read s ...
    res = case [x | (x,t) <- reads lns, ("","") <- lex t] of
            [x] -> x
            _   -> 0
getAutoBnodeIndex _                   = 0

{-
Find all blank nodes that occur
  - any number of times as a subject
  - 0 or 1 times as an object

Such nodes can be output using the "[..]" syntax. To make it simpler
to check we actually store those nodes that can not be expanded.

Note that we do not try and expand any bNode that is used in
a predicate position.

Should probably be using the SubjTree RDFLabel structure but this
is easier for now.

-}

countBnodes :: SortedArcs RDFLabel -> [RDFLabel]
countBnodes (SA as) = snd (foldl' ctr ([],[]) as)
    where
      -- first element of tuple are those blank nodes only seen once,
      -- second element those blank nodes seen multiple times
      --
      inc b@(b1s,bms) l@(Blank _) | l `elem` bms = b
                                  | l `elem` b1s = (delete l b1s, l:bms)
                                  | otherwise    = (l:b1s, bms)
      inc b _ = b

      -- if the bNode appears as a predicate we instantly add it to the
      -- list of nodes not to expand, even if only used once
      incP b@(b1s,bms) l@(Blank _) | l `elem` bms = b
                                   | l `elem` b1s = (delete l b1s, l:bms)
           			   | otherwise    = (b1s, l:bms)
      incP b _ = b

      ctr orig (Arc _ p o) = inc (incP orig p) o

-- N3-like output

-- temporary conversion
quoteB :: Bool -> String -> B.Builder
quoteB f v = B.fromString $ quote f v

{-|
Convert text into a format for display in Turtle. The idea
is to use one double quote unless three are needed, and to
handle adding necessary @\\@ characters, or conversion
for Unicode characters.
-}
quoteText :: T.Text -> B.Builder
quoteText txt = 
  let st = T.unpack txt -- TODO: fix
      qst = quoteB (n==1) st
      n = if '\n' `elem` st || '"' `elem` st then 3 else 1
      qch = B.fromString (replicate n '"')
  in mconcat [qch, qst, qch]

-- TODO: need to be a bit more clever with this than we did in NTriples
--       not sure the following counts as clever enough ...
--  
showScopedName :: ScopedName -> B.Builder
showScopedName = quoteB True . show

formatScopedName :: ScopedName -> M.Map (Maybe T.Text) URI -> B.Builder
formatScopedName sn prmap =
  let nsuri = getScopeURI sn
      local = getLName $ getScopeLocal sn
  in case findPrefix nsuri prmap of
       Just (Just p) -> B.fromText $ quoteT True $ mconcat [p, ":", local]
       _             -> mconcat [ "<"
                                , quoteB True (show nsuri ++ T.unpack local)
                                , ">"
                                ]

formatPrefixLines :: NamespaceMap -> [B.Builder]
formatPrefixLines = map pref . M.assocs
    where
      pref (Just p,u) = mconcat ["@prefix ", B.fromText p, ": <", quoteB True (show u), "> ."]
      pref (_,u)      = mconcat ["@prefix : <", quoteB True (show u), "> ."]
      

maybeExtractList :: 
  SubjTree RDFLabel
  -> PredTree RDFLabel
  -> LabelContext
  -> RDFLabel
  -> Maybe ([RDFLabel], SubjTree RDFLabel, PredTree RDFLabel)
maybeExtractList osubjs oprops lctxt ln =
  let mlst = getCollection osubjs' ln

      -- we only want to send in rdf:first/rdf:rest here
      fprops = filter ((`elem` [resRdfFirst, resRdfRest]) . fst) oprops

      osubjs' =
          case lctxt of
            SubjContext -> (ln, fprops) : osubjs
            _ -> osubjs 

  in case mlst of
    Just (sl, ls, _) -> 
      let oprops' = if lctxt == SubjContext
                    then filter ((`notElem` [resRdfFirst, resRdfRest]) . fst) oprops
                    else oprops
      in Just (ls, sl, oprops')

    _ -> Nothing

formatPlainLit :: T.Text -> B.Builder
formatPlainLit = quoteText

formatLangLit :: T.Text -> LanguageTag -> B.Builder
formatLangLit lit lcode = mconcat [quoteText lit, "@", B.fromText (fromLangTag lcode)]

-- The canonical notation for xsd:double in XSD, with an upper-case E,
-- does not match the syntax used in N3, so we need to convert here.     
-- Rather than converting back to a Double and then displaying that       
-- we just convert E to e for now.      
--      
formatTypedLit :: T.Text -> ScopedName -> B.Builder
formatTypedLit lit dtype
    | dtype == xsdDouble = B.fromText $ T.toLower lit
    | dtype `elem` [xsdBoolean, xsdDecimal, xsdInteger] = B.fromText lit
    | otherwise = mconcat [quoteText lit, "^^", showScopedName dtype]
                           
	       
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