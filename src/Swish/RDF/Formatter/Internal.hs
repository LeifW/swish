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
    , changeState
    , hasMore
    , emptyNgs 
    , getBNodeLabel
    , findMaxBnode
    , splitOnLabel
    , getCollection
    , processArcs
    , findPrefix
      -- N3-like formatting
    , quoteB
    , quoteText
    , showScopedName
    , formatScopedName
    , formatPrefixLines
    , formatPlainLit
    , formatLangLit
    , formatTypedLit
    , insertList
    , nextLine_
    , mapBlankNode_
    , formatPrefixes_
    , formatGraph_
    , formatSubjects_
    , formatProperties_
    , formatObjects_
    , insertBnode_
    , extractList_
    )
where

import Swish.GraphClass (Arc(..), ArcSet)
import Swish.Namespace (ScopedName, getScopeLocal, getScopeURI)
import Swish.QName (getLName)

import Swish.RDF.Graph (RDFGraph, RDFLabel(..), NamespaceMap)
import Swish.RDF.Graph (labels, getArcs
                       , getNamespaces
                       , resRdfFirst, resRdfRest, resRdfNil
                       , quote
                       , quoteT
                       )
import Swish.RDF.Vocabulary (LanguageTag, fromLangTag, xsdBoolean, xsdDecimal, xsdInteger, xsdDouble)

import Control.Monad (liftM)
import Control.Monad.State (State, get, gets, modify, put)

import Data.List (delete, foldl', groupBy, intersperse, partition)
import Data.Monoid (Monoid(..), mconcat)
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

-- | The context for label creation.
--
data LabelContext = SubjContext | PredContext | ObjContext
                    deriving (Eq, Show)

-- | A generator for BNode labels.
data NodeGenState = Ngs
    { nodeMap   :: NodeGenLookupMap
    , nodeGen   :: Word32
    }

-- | Create an empty node generator.
emptyNgs :: NodeGenState
emptyNgs = Ngs M.empty 0

{-|
Get the label text for the blank node, creating a new one
if it has not been seen before.

The label text is currently _:swish<number> where number is
1 or higher. This format may be changed in the future.
-}
getBNodeLabel :: RDFLabel -> NodeGenState -> (B.Builder, Maybe NodeGenState)
getBNodeLabel lab ngs = 
    let cmap = nodeMap ngs
        cval = nodeGen ngs

        (lnum, mngs) = 
            case M.findWithDefault 0 lab cmap of
              0 -> let nval = succ cval
                       nmap = M.insert lab nval cmap
                   in (nval, Just (ngs { nodeGen = nval, nodeMap = nmap }))

              n -> (n, Nothing)

    in ("_:swish" `mappend` B.fromString (show lnum), mngs)


{-|
Process the state, returning a value extracted from it
after updating the state.
-}

changeState ::
    (a -> (b, a)) -> State a b
changeState f = do
  st <- get
  let (rval, nst) = f st
  put nst
  return rval

{-|
Apply the function to the state and return True
if the result is not empty.
-}

hasMore :: (a -> [b]) -> State a Bool
hasMore lens = (not . null . lens) `liftM` get


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

splitOnLabel :: 
    (Eq a) => a -> SubjTree a -> (SubjTree a, PredTree a)
splitOnLabel lbl osubjs = 
    let (bsubj, rsubjs) = partition ((== lbl) . fst) osubjs
        rprops = case bsubj of
                   [(_, rs)] -> rs
                   _         -> []
    in (rsubjs, rprops)
  

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
                           
	       
{-
Add a list inline. We are given the labels that constitute
the list, in order, so just need to display them surrounded
by ().
-}
insertList ::
    (RDFLabel -> State a B.Builder)
    -> [RDFLabel]
    -> State a B.Builder
insertList _ [] = return "()" -- QUS: can this happen in a valid graph?
insertList f xs = do
    ls <- mapM f xs
    return $ mconcat ("( " : intersperse " " ls) `mappend` " )" 

nextLine_ :: (a -> B.Builder) -> (a -> Bool) -> (Bool -> State a ()) -> B.Builder -> State a B.Builder
nextLine_ indent lineBreak setLineBreak str = do
  ind <- gets indent
  brk <- gets lineBreak
  if brk
    then return $ ind `mappend` str
    else do
      --  After first line, always insert line break
      setLineBreak True
      return str
         
mapBlankNode_ :: (a -> NodeGenState) -> (NodeGenState -> State a ()) -> RDFLabel -> State a B.Builder
mapBlankNode_ nodeGenSt setNgs lab = do
  ngs <- gets nodeGenSt
  let (lval, mngs) = getBNodeLabel lab ngs
  case mngs of
    Just ngs' -> setNgs ngs'
    _ -> return ()
  return lval

formatPrefixLines :: NamespaceMap -> [B.Builder]
formatPrefixLines = map pref . M.assocs
    where
      pref (Just p,u) = mconcat ["@prefix ", B.fromText p, ": <", quoteB True (show u), "> ."]
      pref (_,u)      = mconcat ["@prefix : <", quoteB True (show u), "> ."]
      
formatPrefixes_ :: (B.Builder -> State a B.Builder) -> NamespaceMap -> State a B.Builder
formatPrefixes_ nextLine pmap = 
    mconcat `liftM` mapM nextLine (formatPrefixLines pmap)

formatGraph_ :: 
    (B.Builder -> State a ()) -- set indent
    -> (Bool -> State a ())   -- set line-break flag
    -> (RDFGraph -> a -> a)        -- create a new state from the graph
    -> (NamespaceMap -> State a B.Builder) -- format prefixes
    -> (a -> SubjTree RDFLabel)      -- get the subjects
    -> State a B.Builder              -- format the subjects
    -> B.Builder     -- indentation string
    -> B.Builder  -- text to be placed after final statement
    -> Bool       -- True if a line break is to be inserted at the start
    -> Bool       -- True if prefix strings are to be generated
    -> RDFGraph   -- graph to convert
    -> State a B.Builder
formatGraph_ setIndent setLineBreak newState formatPrefixes subjs formatSubjects ind end dobreak dopref gr = do
  setIndent ind
  setLineBreak dobreak
  modify (newState gr)
  
  fp <- if dopref
        then formatPrefixes (getNamespaces gr)
        else return mempty
  more <- hasMore subjs
  if more
    then do
      fr <- formatSubjects
      return $ mconcat [fp, fr, end]
    else return fp

formatSubjects_ ::
    State a RDFLabel     -- ^ next subject
    -> (LabelContext -> RDFLabel -> State a B.Builder)  -- ^ convert label into text
    -> (a -> PredTree RDFLabel) -- ^ extract properties
    -> (RDFLabel -> B.Builder -> State a B.Builder)   -- ^ format properties
    -> (a -> SubjTree RDFLabel) -- ^ extract subjects
    -> (B.Builder -> State a B.Builder) -- ^ next line
    -> State a B.Builder
formatSubjects_ nextSubject formatLabel props formatProperties subjs nextLine = do
  sb    <- nextSubject
  sbstr <- formatLabel SubjContext sb
  
  flagP <- hasMore props
  if flagP
    then do
      prstr <- formatProperties sb sbstr
      flagS <- hasMore subjs
      if flagS
        then do
          fr <- formatSubjects_ nextSubject formatLabel props formatProperties subjs nextLine
          return $ mconcat [prstr, " .", fr]
        else return prstr
           
    else do
      txt <- nextLine sbstr
    
      flagS <- hasMore subjs
      if flagS
        then do
          fr <- formatSubjects_ nextSubject formatLabel props formatProperties subjs nextLine
          return $ mconcat [txt, " .", fr]
        else return txt


{-
TODO: now we are throwing a Builder around it is awkward to
get the length of the text to calculate the indentation

So

  a) change the indentation scheme
  b) pass around text instead of builder

mkIndent :: L.Text -> L.Text
mkIndent inVal = L.replicate (L.length inVal) " "
-}

hackIndent :: B.Builder
hackIndent = "    "

formatProperties_ :: 
    (RDFLabel -> State a RDFLabel)        -- ^ next property for the given subject
    -> (LabelContext -> RDFLabel -> State a B.Builder) -- ^ convert label into text
    -> (RDFLabel -> RDFLabel -> B.Builder -> State a B.Builder) -- ^ format objects
    -> (a -> PredTree RDFLabel) -- ^ extract properties
    -> (B.Builder -> State a B.Builder) -- ^ next line
    -> RDFLabel             -- ^ property being processed
    -> B.Builder            -- ^ current output
    -> State a B.Builder
formatProperties_ nextProperty formatLabel formatObjects props nextLine sb sbstr = do
  pr <- nextProperty sb
  prstr <- formatLabel PredContext pr
  obstr <- formatObjects sb pr $ mconcat [sbstr, " ", prstr]
  more  <- hasMore props
  let sbindent = hackIndent -- mkIndent sbstr
  if more
    then do
      fr <- formatProperties_ nextProperty formatLabel formatObjects props nextLine sb sbindent
      nl <- nextLine $ obstr `mappend` " ;"
      return $ nl `mappend` fr
    else nextLine obstr

formatObjects_ :: 
    (RDFLabel -> RDFLabel -> State a RDFLabel) -- ^ get the next object for the (subject,property) pair
    -> (LabelContext -> RDFLabel -> State a B.Builder) -- ^ format a label
    -> (a -> [RDFLabel]) -- ^ extract objects
    -> (B.Builder -> State a B.Builder) -- ^ new line
    -> RDFLabel      -- ^ subject
    -> RDFLabel      -- ^ property
    -> B.Builder     -- ^ current text
    -> State a B.Builder
formatObjects_ nextObject formatLabel objs nextLine sb pr prstr = do
  ob    <- nextObject sb pr
  obstr <- formatLabel ObjContext ob
  more  <- hasMore objs
  if more
    then do
      let prindent = hackIndent -- mkIndent prstr
      fr <- formatObjects_ nextObject formatLabel objs nextLine sb pr prindent
      nl <- nextLine $ mconcat [prstr, " ", obstr, ","]
      return $ nl `mappend` fr
    else return $ mconcat [prstr, " ", obstr]

{-
Processing a Bnode when not a subject.
-}
insertBnode_ ::
    (a -> SubjTree RDFLabel)  -- ^ extract subjects
    -> (a -> PredTree RDFLabel) -- ^ extract properties
    -> (a -> [RDFLabel]) -- ^ extract objects
    -> (a -> SubjTree RDFLabel -> PredTree RDFLabel -> [RDFLabel] -> a) -- ^ update state to new settings
    -> (RDFLabel -> B.Builder -> State a B.Builder) -- ^ format properties
    -> RDFLabel
    -> State a B.Builder
insertBnode_ subjs props objs updateState formatProperties lbl = do
  ost <- get
  let osubjs = subjs ost
      (rsubjs, rprops) = splitOnLabel lbl osubjs
  put $ updateState ost rsubjs rprops []
  flag <- hasMore props
  txt <- if flag
         then (`mappend` "\n") `liftM` formatProperties lbl ""
         else return ""

  -- restore the original data (where appropriate)
  nst <- get
  let slist  = map fst $ subjs nst
      nsubjs = filter (\(l,_) -> l `elem` slist) osubjs

  put $ updateState nst nsubjs (props ost) (objs ost)

  -- TODO: handle indentation?
  return $ mconcat ["[", txt, "]"]


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

extractList_ :: 
    (a -> SubjTree RDFLabel) -- ^ extract subjects
    -> (a -> PredTree RDFLabel) -- ^ extract properties
    -> (SubjTree RDFLabel -> State a ())  -- ^ set subjects
    -> (PredTree RDFLabel -> State a ())  -- ^ set properties
    -> LabelContext 
    -> RDFLabel 
    -> State a (Maybe [RDFLabel])
extractList_ subjs props setSubjs setProps lctxt ln = do
  osubjs <- gets subjs
  oprops <- gets props
  case maybeExtractList osubjs oprops lctxt ln of
    Just (ls, osubjs', oprops') -> do
      setSubjs osubjs'
      setProps oprops'
      return (Just ls)

    _ -> return Nothing
  
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
