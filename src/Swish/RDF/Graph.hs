{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE OverloadedStrings #-}

--------------------------------------------------------------------------------
--  See end of this file for licence information.
--------------------------------------------------------------------------------
-- |
--  Module      :  Graph
--  Copyright   :  (c) 2003, Graham Klyne, 2009 Vasili I Galchin, 2011, 2012 Douglas Burke
--  License     :  GPL V2
--
--  Maintainer  :  Douglas Burke
--  Stability   :  experimental
--  Portability :  CPP, FlexibleInstances, MultiParamTypeClasses, TypeSynonymInstances, OverloadedStrings
--
--  This module defines a memory-based RDF graph instance.
--
--------------------------------------------------------------------------------

------------------------------------------------------------
-- Simple labelled directed graph value
------------------------------------------------------------

module Swish.RDF.Graph
    ( 
      -- * Labels
      RDFLabel(..), ToRDFLabel(..), FromRDFLabel(..)
    , isLiteral, isUntypedLiteral, isTypedLiteral, isXMLLiteral
    , isDatatyped, isMemberProp, isUri, isBlank, isQueryVar
    , getLiteralText, getScopedName, makeBlank
    , quote
    , quoteT
      
      -- * RDF Graphs
    , RDFTriple
    , toRDFTriple, fromRDFTriple
    , NSGraph(..)
    , RDFGraph
    , toRDFGraph, emptyRDFGraph {-, updateRDFGraph-}
    , NamespaceMap, RevNamespaceMap, RevNamespace
    , emptyNamespaceMap
    , LookupFormula(..), Formula, FormulaMap, emptyFormulaMap
    , addArc, merge
    , allLabels, allNodes, remapLabels, remapLabelList
    , newNode, newNodes
    , setNamespaces, getNamespaces
    , setFormulae, getFormulae, setFormula, getFormula
      
    -- * Re-export from GraphClass
    --
    -- | Note that @asubj@, @apred@ and @aobj@ have been
    -- removed in version @0.7.0.0@; use 'arcSubj', 'arcPred'
    -- or 'arcObj' instead.
    --
    , LDGraph(..), Label (..), Arc(..)
    , arc, Selector
      
    -- * Selected RDFLabel values
    --                                
    -- | The 'ToRDFLabel' instance of 'ScopedName' can also be used                                     
    -- to easily construct 'RDFLabel' versions of the terms defined
    -- in `Swish.RDF.Vocabulary`.
    
    -- ** RDF terms                                          
    --                                          
    -- | These terms are described in <http://www.w3.org/TR/rdf-syntax-grammar/>;                                          
    -- the version used is \"W3C Recommendation 10 February 2004\", <http://www.w3.org/TR/2004/REC-rdf-syntax-grammar-20040210/>.
    --                                          
    -- Some terms are listed within the RDF Schema terms below since their definition                                            
    -- is given within the RDF Schema document.                                          
    --                                          
    , resRdfRDF                                          
    , resRdfDescription      
    , resRdfID
    , resRdfAbout
    , resRdfParseType
    , resRdfResource
    , resRdfLi
    , resRdfNodeID
    , resRdfDatatype
    , resRdf1, resRdf2, resRdfn
    -- ** RDF Schema terms
    --                                 
    -- | These are defined by <http://www.w3.org/TR/rdf-schema/>; the version
    -- used is \"W3C Recommendation 10 February 2004\", <http://www.w3.org/TR/2004/REC-rdf-schema-20040210/>.
                        
    -- *** Classes
    --                                 
    -- | See the \"Classes\" section at <http://www.w3.org/TR/rdf-schema/#ch_classes> for more information.
    , resRdfsResource
    , resRdfsClass
    , resRdfsLiteral
    , resRdfsDatatype
    , resRdfXMLLiteral
    , resRdfProperty
    -- *** Properties
    --                                 
    -- | See the \"Properties\" section at <http://www.w3.org/TR/rdf-schema/#ch_classes> for more information.
    , resRdfsRange
    , resRdfsDomain
    , resRdfType
    , resRdfsSubClassOf
    , resRdfsSubPropertyOf
    , resRdfsLabel
    , resRdfsComment
    -- *** Containers
    --
    -- | See the \"Container Classes and Properties\" section at <http://www.w3.org/TR/rdf-schema/#ch_containervocab>.
    , resRdfsContainer
    , resRdfBag
    , resRdfSeq                                 
    , resRdfAlt  
    , resRdfsContainerMembershipProperty
    , resRdfsMember
    -- *** Collections
    --
    -- | See the \"Collections\" section at <http://www.w3.org/TR/rdf-schema/#ch_collectionvocab>.
    , resRdfList    
    , resRdfFirst
    , resRdfRest 
    , resRdfNil 
    -- *** Reification Vocabulary 
    --  
    -- | See the \"Reification Vocabulary\" section at <http://www.w3.org/TR/rdf-schema/#ch_reificationvocab>.
    , resRdfStatement  
    , resRdfSubject  
    , resRdfPredicate  
    , resRdfObject  
    -- *** Utility Properties 
    --  
    -- | See the \"Utility Properties\" section at <http://www.w3.org/TR/rdf-schema/#ch_utilvocab>.
    , resRdfsSeeAlso
    , resRdfsIsDefinedBy
    , resRdfValue  
    
    -- ** OWL     
    , resOwlSameAs
                    
    -- ** Miscellaneous     
    , resRdfdGeneralRestriction
    , resRdfdOnProperties, resRdfdConstraint, resRdfdMaxCardinality
    , resLogImplies
      
    -- * Exported for testing
    , grMatchMap, grEq
    , mapnode, maplist
    )
    where

import Swish.Namespace
    ( Namespace, makeNamespace, getNamespaceTuple
    , getScopedNameURI
    , ScopedName
    , getScopeLocal, getScopeNamespace
    , getQName
    , makeQNameScopedName
    , makeURIScopedName
    , nullScopedName
    )

import Swish.RDF.Vocabulary
{-    
    ( namespaceRDF
    , langTag, isLang
    , rdfType
    , rdfFirst, rdfRest, rdfNil, rdfXMLLiteral
    , rdfsMember
    , rdfdGeneralRestriction
    , rdfdOnProperties, rdfdConstraint, rdfdMaxCardinality
    , owlSameAs, logImplies
    , xsdBoolean, xsdDecimal, xsdFloat, xsdDouble, xsdInteger
    , xsdDateTime, xsdDate                                                
    )
-}

import Swish.GraphClass (LDGraph(..), Label (..), Arc(..), Selector)
import Swish.GraphClass (arc, arcLabels)
import Swish.GraphMatch (LabelMap, ScopedLabel(..))
import Swish.GraphMatch (graphMatch)
import Swish.QName (QName)

import Swish.Utils.LookupMap
    ( LookupMap(..), LookupEntryClass(..)
    , listLookupMap
    , mapFind, mapFindMaybe, mapReplaceOrAdd, mapAddIfNew
    , mapVals, mapKeys )

import qualified Data.Foldable as Foldable
import qualified Data.Traversable as Traversable

import qualified Data.Text as T
import qualified Data.Text.Read as T
-- import qualified Data.Text.Lazy as L
-- import Data.Text.Format (format)
-- import Data.Text.Buildable
-- import Data.Text.Format.Types (Only(..))

import Control.Applicative (Applicative, liftA, (<$>), (<*>))

import Network.URI (URI)

import Data.Monoid (Monoid(..))
import Data.Maybe (mapMaybe)
import Data.Char (ord, isDigit)
import Data.Hashable (hashWithSalt)
import Data.List (intersect, union, foldl')
import Data.Ord (comparing)
import Data.Word

import Data.String (IsString(..))
import Data.Time (UTCTime, Day, ParseTime, parseTime, formatTime)
import System.Locale (defaultTimeLocale)  
import Text.Printf

#if defined(__GLASGOW_HASKELL__) && (__GLASGOW_HASKELL__ >= 701)
import Data.Tuple (swap)
#else
swap :: (a,b) -> (b,a)
swap (a,b) = (b,a)
#endif

-- | RDF graph node values
--
--  cf. <http://www.w3.org/TR/rdf-concepts/#section-Graph-syntax>
--
--  This is extended from the RDF abstract graph syntax in the
--  following ways:
--
--  (a) a graph can be part of a resource node or blank node
--      (cf. Notation3 formulae)
--
--  (b) a \"variable\" node option is distinguished from a
--      blank node.
--      I have found this useful for encoding and handling
--      queries, even though query variables can be expressed
--      as blank nodes.
--
--  (c) a \"NoNode\" option is defined.
--      This might otherwise be handled by @Maybe (RDFLabel g)@.
--
-- Prior to version @0.7.0.0@, literals were represented by a
-- single constructor, @Lit@, with an optional argument. Language
-- codes for literals was also stored as a 'ScopedName' rather than
-- as a 'LanguageTag'.
--
data RDFLabel =
      Res ScopedName                    -- ^ resource
    | Lit T.Text                        -- ^ a plain literal
    | LangLit T.Text LanguageTag        -- ^ a literal with an associated language
    | TypedLit T.Text ScopedName        -- ^ a literal with an associated data type
    | Blank String                      -- ^ blank node
    | Var String                        -- ^ variable (not used in ordinary graphs)
    | NoNode                            -- ^ no node  (not used in ordinary graphs)

-- | Define equality of nodes possibly based on different graph types.
--
-- The equality of literals is taken from section 6.5.1 ("Literal
-- Equality") of the RDF Concepts and Abstract Document,
-- <http://www.w3.org/TR/2004/REC-rdf-concepts-20040210/#section-Literal-Equality>.
--
instance Eq RDFLabel where
    Res q1   == Res q2   = q1 == q2
    Blank b1 == Blank b2 = b1 == b2
    Var v1   == Var v2   = v1 == v2

    Lit s1         == Lit s2         = s1 == s2
    LangLit s1 l1  == LangLit s2 l2  = s1 == s2 && l1 == l2
    TypedLit s1 t1 == TypedLit s2 t2 = s1 == s2 && t1 == t2

    _  == _ = False

instance Show RDFLabel where
    show (Res sn)           = show sn
    show (Lit st)           = quote1Str st
    show (LangLit st lang)  = quote1Str st ++ "@"  ++ T.unpack (fromLangTag lang)
    show (TypedLit st dtype) 
        | dtype `elem` [xsdBoolean, xsdDouble, xsdDecimal, xsdInteger] = T.unpack st
        | otherwise  = quote1Str st ++ "^^" ++ show dtype

    {-
    show (Lit st (Just nam))
        | isLang nam = quote1Str st ++ "@"  ++ T.unpack (langTag nam)
        | nam `elem` [xsdBoolean, xsdDouble, xsdDecimal, xsdInteger] = T.unpack st
        | otherwise  = quote1Str st ++ "^^" ++ show nam
    -}

    show (Blank ln)         = "_:"++ln
    show (Var ln)           = '?' : ln
    show NoNode             = "<NoNode>"

instance Ord RDFLabel where
    -- Optimize some common cases..
    compare (Res sn1)      (Res sn2)      = compare sn1 sn2
    compare (Blank ln1)    (Blank ln2)    = compare ln1 ln2
    compare (Res _)        (Blank _)      = LT
    compare (Blank _)      (Res _)        = GT

    compare (Lit s1)       (Lit s2)       = compare s1 s2

    -- .. else use show string comparison
    compare l1 l2 = comparing show l1 l2
    
    {- <= is not used if compare is provided
    -- Similarly for <=
    (Res qn1)   <= (Res qn2)      = qn1 <= qn2
    (Blank ln1) <= (Blank ln2)    = ln1 <= ln2
    (Res _)     <= (Blank _)      = True
    (Blank _)   <= (Res _)        = False
    l1 <= l2                      = show l1 <= show l2
    -}
    
instance Label RDFLabel where
    labelIsVar (Blank _)    = True
    labelIsVar (Var _)      = True
    labelIsVar _            = False

    getLocal   (Blank loc)  = loc
    getLocal   (Var   loc)  = '?':loc
    getLocal   (Res   sn)   = "Res_" ++ T.unpack (getScopeLocal sn)
    getLocal   (NoNode)     = "None"
    getLocal   _            = "Lit_"

    makeLabel  ('?':loc)    = Var loc
    makeLabel  loc          = Blank loc

    labelHash seed lb       = hashWithSalt seed (showCanon lb)

instance IsString RDFLabel where
  fromString = Lit . T.pack

{-|
A type that can be converted to a RDF Label.

The String instance converts to an untyped literal
(so no language tag is assumed).

The `UTCTime` and `Day` instances assume values are in UTC.
 
The conversion for XSD types attempts to use the
canonical form described in section 2.3.1 of
<http://www.w3.org/TR/2004/REC-xmlschema-2-20041028/#lexical-space>.
  
Note that this is very similar to
'Swish.RDF.RDFDatatype.toRDFLabel' and should be moved into
a @Swish.RDF.Datatype@ module.
-}

class ToRDFLabel a where
  toRDFLabel :: a -> RDFLabel
  
{-|
A type that can be converted from a RDF Label,
with the possibility of failure.
 
The String instance converts from an untyped literal
(so it can not be used with a string with a language tag).

The following conversions are supported for common XSD
types (out-of-band values result in @Nothing@):

 - @xsd:boolean@ to @Bool@

 - @xsd:integer@ to @Int@ and @Integer@

 - @xsd:float@ to @Float@

 - @xsd:double@ to @Double@

 - @xsd:dateTime@ to @UTCTime@

 - @xsd:date@ to @Day@

Note that this is very similar to
'Swish.RDF.RDFDatatype.fromRDFLabel' and should be moved into
a @Swish.RDF.Datatype@ module.
-}

class FromRDFLabel a where
  fromRDFLabel :: RDFLabel -> Maybe a

-- instances for type conversion to/from RDFLabel
  
-- | This is just @id@.
instance ToRDFLabel RDFLabel where
  toRDFLabel = id
  
-- | This is just @Just . id@.  
instance FromRDFLabel RDFLabel where
  fromRDFLabel = Just . id
  
-- TODO: remove this hack when finished conversion to Text
maybeReadStr :: (Read a) => T.Text -> Maybe a  
maybeReadStr txt = case reads (T.unpack txt) of
  [(val, "")] -> Just val
  _ -> Nothing
  
maybeRead :: T.Reader a -> T.Text -> Maybe a
maybeRead rdr inTxt = 
  case rdr inTxt of
    Right (val, "") -> Just val
    _ -> Nothing
    
fLabel :: (T.Text -> Maybe a) -> ScopedName -> RDFLabel -> Maybe a
fLabel conv dtype (TypedLit xs dt) | dt == dtype = conv xs
                                   | otherwise   = Nothing
fLabel _    _     _ = Nothing
  
tLabel :: (Show a) => ScopedName -> (String -> T.Text) -> a -> RDFLabel                      
tLabel dtype conv = flip TypedLit dtype . conv . show                      

-- | The character is converted to an untyped literal of length one.
instance ToRDFLabel Char where
  toRDFLabel = Lit . T.singleton

-- | The label must be an untyped literal containing a single character.
instance FromRDFLabel Char where
  fromRDFLabel (Lit cs) | T.compareLength cs 1 == EQ = Just (T.head cs)
                        | otherwise = Nothing
  fromRDFLabel _ = Nothing

-- | Strings are converted to untyped literals.
instance ToRDFLabel String where
  toRDFLabel = Lit . T.pack

-- | Only untyped literals are converted to strings.
instance FromRDFLabel String where
  fromRDFLabel (Lit xs) = Just (T.unpack xs)
  fromRDFLabel _        = Nothing

textToBool :: T.Text -> Maybe Bool
textToBool s | s `elem` ["1", "true"]  = Just True
             | s `elem` ["0", "false"] = Just False
             | otherwise               = Nothing

-- | Converts to a literal with a @xsd:boolean@ datatype.
instance ToRDFLabel Bool where
  toRDFLabel b = TypedLit (if b then "true" else "false") xsdBoolean
                                                 
-- | Converts from a literal with a @xsd:boolean@ datatype. The
-- literal can be any of the supported XSD forms - e.g. \"0\" or
-- \"true\".
instance FromRDFLabel Bool where
  fromRDFLabel = fLabel textToBool xsdBoolean

-- fromRealFloat :: (RealFloat a, Buildable a) => ScopedName -> a -> RDFLabel
fromRealFloat :: (RealFloat a, PrintfArg a) => ScopedName -> a -> RDFLabel
fromRealFloat dtype f | isNaN f      = toL "NaN"
                      | isInfinite f = toL $ if f > 0.0 then "INF" else "-INF"
                      -- 
                      -- Would like to use Data.Text.Format.format but there are                                                                        
                      -- issues with this module; 0.3.0.2 doesn't build under
                      -- 6.12.3 due to a missing RelaxedPolyRec language extension
                      -- and it relies on double-conversion which has issues
                      -- when used in ghci due to a dlopen issue with libstdc++.
                      -- 
                      -- -- | otherwise    = toL $ L.toStrict $ format "{}" (Only f)  
                      -- 
                      | otherwise    = toL $ T.pack $ printf "%E" f
                        
                        where
                          toL = flip TypedLit dtype

-- textToRealFloat :: (RealFloat a) => (a -> Maybe a) -> T.Text -> Maybe a
textToRealFloat :: (RealFloat a, Read a) => (a -> Maybe a) -> T.Text -> Maybe a
textToRealFloat conv = rconv
    where
      rconv "NaN"  = Just (0.0/0.0) -- how best to create a NaN?
      rconv "INF"  = Just (1.0/0.0) -- ditto for Infinity
      rconv "-INF" = Just ((-1.0)/0.0)
      rconv ival 
        -- xsd semantics allows "2." but Haskell syntax does not.
        | T.null ival = Nothing
          
        | otherwise = case maybeReadStr ival of
          Just val -> conv val
          _        -> if T.last ival == '.' -- could drop the check
                      then maybeReadStr (T.snoc ival '0') >>= conv
                      else Nothing
                               
        {-

        Unfortunately T.rational does not handle "3.01e4" the same
        as read; see https://bitbucket.org/bos/text/issue/7/

        | otherwise = case maybeRead T.rational ival of
          Just val -> conv val
          _        -> if T.last ival == '.' -- could drop the check
                      then maybeRead T.rational (T.snoc ival '0') >>= conv
                      else Nothing
        -}
                        
        -- not sure the above is any improvement on the following
        -- -- | T.last ival == '.' = maybeRead T.rational (T.snoc ival '0') >>= conv
        -- -- | otherwise          = maybeRead T.rational ival >>= conv
      
textToFloat :: T.Text -> Maybe Float
textToFloat = 
  let -- assume that an invalid value (NaN/Inf) from maybeRead means
      -- that the value is out of bounds for Float so we do not
      -- convert
      conv f | isNaN f || isInfinite f = Nothing
             | otherwise               = Just f
  in textToRealFloat conv

textToDouble :: T.Text -> Maybe Double      
textToDouble = textToRealFloat Just

-- | Converts to a literal with a @xsd:float@ datatype.
instance ToRDFLabel Float where
  toRDFLabel = fromRealFloat xsdFloat
  
-- | Converts from a literal with a @xsd:float@ datatype.
-- The conversion will fail if the value is outside the valid range of
-- a Haskell `Float`.
instance FromRDFLabel Float where
  fromRDFLabel = fLabel textToFloat xsdFloat
                 
-- | Converts to a literal with a @xsd:double@ datatype.
instance ToRDFLabel Double where
  toRDFLabel = fromRealFloat xsdDouble
  
-- | Converts from a literal with a @xsd:double@ datatype.
instance FromRDFLabel Double where
  fromRDFLabel = fLabel textToDouble xsdDouble
  
-- TODO: are there subtypes of xsd::integer that are  
--       useful here?  
--         
-- TODO: add in support for Int8/..., Word8/...  
--  

-- | Converts to a literal with a @xsd:integer@ datatype.
instance ToRDFLabel Int where
  toRDFLabel = tLabel xsdInteger T.pack

{-
Since decimal will just over/under-flow when converting to Int
we go via Integer and explicitly check for overflow.
-}

textToInt :: T.Text -> Maybe Int
textToInt s = 
  let conv :: Integer -> Maybe Int
      conv i = 
        let lb = fromIntegral (minBound :: Int)
            ub = fromIntegral (maxBound :: Int)
        in if (i >= lb) && (i <= ub) then Just (fromIntegral i) else Nothing
  
  in maybeRead (T.signed T.decimal) s >>= conv

-- | Converts from a literal with a @xsd:integer@ datatype.
-- The conversion will fail if the value is outside the valid range of
-- a Haskell `Int`.
instance FromRDFLabel Int where
  fromRDFLabel = fLabel textToInt xsdInteger

-- | Converts to a literal with a @xsd:integer@ datatype.
instance ToRDFLabel Integer where
  toRDFLabel = tLabel xsdInteger T.pack

-- | Converts from a literal with a @xsd:integer@ datatype.
instance FromRDFLabel Integer where
  fromRDFLabel = fLabel (maybeRead (T.signed T.decimal)) xsdInteger

{-
Support an ISO-8601 style format supporting

  2005-02-28T00:00:00Z
  2004-12-31T19:01:00-05:00
  2005-07-14T03:18:56.234+01:00

fromUTCFormat is used to convert UTCTime to a string
for storage within a Lit.

toUTCFormat is used to convert a string into UTCTime;
we have to support 
   no time zone
   Z
   +/-HH:MM

which means a somewhat messy convertor, which is written
for clarity rather than speed.
-}

fromUTCFormat :: UTCTime -> String
fromUTCFormat = formatTime defaultTimeLocale "%FT%T%QZ"
  
fromDayFormat :: Day -> String
fromDayFormat = formatTime defaultTimeLocale "%FZ"
  
toTimeFormat :: (ParseTime a) => String -> String -> Maybe a
toTimeFormat fmt inVal =
  let fmtHHMM = fmt ++ "%z"
      fmtZ = fmt ++ "Z"
      pt f = parseTime defaultTimeLocale f inVal
  in case pt fmtHHMM of
    o@(Just _) -> o
    _ -> case pt fmtZ of
      o@(Just _) -> o
      _ -> pt fmt 
  
toUTCFormat :: T.Text -> Maybe UTCTime
toUTCFormat = toTimeFormat "%FT%T%Q" . T.unpack
    
toDayFormat :: T.Text -> Maybe Day
toDayFormat = toTimeFormat "%F" . T.unpack
    
-- | Converts to a literal with a @xsd:datetime@ datatype.
instance ToRDFLabel UTCTime where
  toRDFLabel = flip TypedLit xsdDateTime . T.pack . fromUTCFormat
  
-- | Converts from a literal with a @xsd:datetime@ datatype.
instance FromRDFLabel UTCTime where
  fromRDFLabel = fLabel toUTCFormat xsdDateTime
  
-- | Converts to a literal with a @xsd:date@ datatype.
instance ToRDFLabel Day where
  toRDFLabel = flip TypedLit xsdDate . T.pack . fromDayFormat

-- | Converts from a literal with a @xsd:date@ datatype.
instance FromRDFLabel Day where
  fromRDFLabel = fLabel toDayFormat xsdDate
  
-- | Converts to a Resource.
instance ToRDFLabel ScopedName where  
  toRDFLabel = Res

-- | Converts from a Resource.
instance FromRDFLabel ScopedName where
  fromRDFLabel (Res sn) = Just sn
  fromRDFLabel _        = Nothing
  
-- | Converts to a Resource.
instance ToRDFLabel QName where  
  toRDFLabel = Res . makeQNameScopedName Nothing
  
-- | Converts from a Resource.
instance FromRDFLabel QName where
  fromRDFLabel (Res sn) = Just $ getQName sn
  fromRDFLabel _        = Nothing
  
-- | Converts to a Resource.
instance ToRDFLabel URI where  
  toRDFLabel = Res . makeURIScopedName
  
-- | Converts from a Resource.
instance FromRDFLabel URI where
  fromRDFLabel (Res sn) = Just $ getScopedNameURI sn
  fromRDFLabel _        = Nothing

-- | Get the canonical string for RDF label.
--
--  This is used for hashing, so that equivalent labels always return
--  the same hash value.
--
--  TODO: can remove the use of quote1Str as all we care about is
--  a unique output, not that it is valid in any RDF format. Also
--  rename to showForHash or something like that, since it is only used
--  for this purpose.
--
showCanon :: RDFLabel -> String
showCanon (Res sn)           = "<"++show (getScopedNameURI sn)++">"
showCanon (Lit st)           = show st
showCanon (LangLit st lang)  = quote1Str st ++ "@"  ++ T.unpack (fromLangTag lang)
showCanon (TypedLit st dt)   = quote1Str st ++ "^^" ++ show (getScopedNameURI dt)
showCanon s                  = show s

-- | See `quote`.
quoteT :: Bool -> T.Text -> T.Text
quoteT f = T.pack . quote f . T.unpack 

{-| N3-style quoting rules for a string.

TODO: when flag is `False` need to worry about multiple quotes (> 2)
in a row.
-}

quote :: 
  Bool  -- ^ @True@ if the string is to be displayed using one rather than three quotes.
  -> String -- ^ String to quote.
  -> String
quote _     []           = ""
quote False s@(c:'"':[]) | c == '\\'  = s -- handle triple-quoted strings ending in "
                         | otherwise  = [c, '\\', '"']

quote True  ('"': st)    = '\\':'"': quote True  st
quote True  ('\n':st)    = '\\':'n': quote True  st

quote True  ('\t':st)    = '\\':'t': quote True  st
quote False ('"': st)    =      '"': quote False st
quote False ('\n':st)    =     '\n': quote False st
quote False ('\t':st)    =     '\t': quote False st
quote f ('\r':st)    = '\\':'r': quote f st
quote f ('\\':st)    = '\\':'\\': quote f st -- not sure about this
quote f (c:st) = 
  let nc = ord c
      rst = quote f st
      
      -- lazy way to convert to a string
      hstr = printf "%08X" nc
      ustr = hstr ++ rst

  in if nc > 0xffff 
     then '\\':'U': ustr
     else if nc > 0x7e || nc < 0x20
          then '\\':'u': drop 4 ustr
          else c : rst

-- surround a string with quotes ("...")

quote1Str :: T.Text -> String
quote1Str t = '"' : quote False (T.unpack t) ++ "\""

---------------------------------------------------------
--  Selected RDFLabel values
---------------------------------------------------------

-- | @rdf:type@ from <http://www.w3.org/TR/rdf-schema/#ch_type>.
resRdfType :: RDFLabel
resRdfType = Res rdfType 

-- | @rdf:List@ from <http://www.w3.org/TR/rdf-schema/#ch_list>.
resRdfList :: RDFLabel
resRdfList = Res rdfList

-- | @rdf:first@ from <http://www.w3.org/TR/rdf-schema/#ch_first>.
resRdfFirst :: RDFLabel
resRdfFirst = Res rdfFirst 

-- | @rdf:rest@ from <http://www.w3.org/TR/rdf-schema/#ch_rest>.
resRdfRest :: RDFLabel
resRdfRest = Res rdfRest

-- | @rdf:nil@ from <http://www.w3.org/TR/rdf-schema/#ch_nil>.
resRdfNil :: RDFLabel
resRdfNil = Res rdfNil

-- | @rdfs:member@ from <http://www.w3.org/TR/rdf-schema/#ch_member>.
resRdfsMember :: RDFLabel
resRdfsMember = Res rdfsMember

-- | @rdfd:GeneralRestriction@.
resRdfdGeneralRestriction :: RDFLabel
resRdfdGeneralRestriction = Res rdfdGeneralRestriction

-- | @rdfd:onProperties@.
resRdfdOnProperties :: RDFLabel
resRdfdOnProperties       = Res rdfdOnProperties

-- | @rdfd:constraint@.
resRdfdConstraint :: RDFLabel
resRdfdConstraint         = Res rdfdConstraint

-- | @rdfd:maxCardinality@.
resRdfdMaxCardinality :: RDFLabel
resRdfdMaxCardinality     = Res rdfdMaxCardinality

-- | @rdfs:seeAlso@ from <http://www.w3.org/TR/rdf-schema/#ch_seealso>.
resRdfsSeeAlso :: RDFLabel
resRdfsSeeAlso = Res rdfsSeeAlso

-- | @rdf:value@ from <http://www.w3.org/TR/rdf-schema/#ch_value>.
resRdfValue :: RDFLabel
resRdfValue = Res rdfValue

-- | @owl:sameAs@.
resOwlSameAs :: RDFLabel
resOwlSameAs = Res owlSameAs

-- | @log:implies@.
resLogImplies :: RDFLabel
resLogImplies = Res logImplies

-- | @rdfs:label@ from <http://www.w3.org/TR/rdf-schema/#ch_label>.
resRdfsLabel :: RDFLabel
resRdfsLabel = Res rdfsLabel

-- | @rdfs:comment@ from <http://www.w3.org/TR/rdf-schema/#ch_comment>.
resRdfsComment :: RDFLabel
resRdfsComment = Res rdfsComment

-- | @rdf:Property@ from <http://www.w3.org/TR/rdf-schema/#ch_property>.
resRdfProperty :: RDFLabel
resRdfProperty = Res rdfProperty

-- | @rdfs:subPropertyOf@ from <http://www.w3.org/TR/rdf-schema/#ch_subpropertyof>.
resRdfsSubPropertyOf :: RDFLabel
resRdfsSubPropertyOf = Res rdfsSubPropertyOf

-- | @rdfs:subClassOf@ from <http://www.w3.org/TR/rdf-schema/#ch_subclassof>.
resRdfsSubClassOf :: RDFLabel
resRdfsSubClassOf = Res rdfsSubClassOf

-- | @rdfs:Class@ from <http://www.w3.org/TR/rdf-schema/#ch_class>.
resRdfsClass :: RDFLabel
resRdfsClass = Res rdfsClass

-- | @rdfs:Literal@ from <http://www.w3.org/TR/rdf-schema/#ch_literal>.
resRdfsLiteral :: RDFLabel
resRdfsLiteral = Res rdfsLiteral

-- | @rdfs:Datatype@ from <http://www.w3.org/TR/rdf-schema/#ch_datatype>.
resRdfsDatatype :: RDFLabel
resRdfsDatatype = Res rdfsDatatype

-- | @rdf:XMLLiteral@ from <http://www.w3.org/TR/rdf-schema/#ch_xmlliteral>.
resRdfXMLLiteral :: RDFLabel
resRdfXMLLiteral = Res rdfXMLLiteral

-- | @rdfs:range@ from <http://www.w3.org/TR/rdf-schema/#ch_range>.
resRdfsRange :: RDFLabel
resRdfsRange = Res rdfsRange

-- | @rdfs:domain@ from <http://www.w3.org/TR/rdf-schema/#ch_domain>.
resRdfsDomain :: RDFLabel
resRdfsDomain = Res rdfsDomain

-- | @rdfs:Container@ from <http://www.w3.org/TR/rdf-schema/#ch_container>.
resRdfsContainer :: RDFLabel
resRdfsContainer = Res rdfsContainer

-- | @rdf:Bag@ from <http://www.w3.org/TR/rdf-schema/#ch_bag>.
resRdfBag :: RDFLabel
resRdfBag = Res rdfBag

-- | @rdf:Seq@ from <http://www.w3.org/TR/rdf-schema/#ch_seq>.
resRdfSeq :: RDFLabel
resRdfSeq = Res rdfSeq

-- | @rdf:Alt@ from <http://www.w3.org/TR/rdf-schema/#ch_alt>.
resRdfAlt :: RDFLabel
resRdfAlt = Res rdfAlt

-- | @rdfs:ContainerMembershipProperty@ from <http://www.w3.org/TR/rdf-schema/#ch_containermembershipproperty>.
resRdfsContainerMembershipProperty :: RDFLabel
resRdfsContainerMembershipProperty = Res rdfsContainerMembershipProperty

-- | @rdfs:isDefinedBy@ from <http://www.w3.org/TR/rdf-schema/#ch_isdefinedby>.
resRdfsIsDefinedBy :: RDFLabel
resRdfsIsDefinedBy = Res rdfsIsDefinedBy

-- | @rdfs:Resource@ from <http://www.w3.org/TR/rdf-schema/#ch_resource>.
resRdfsResource :: RDFLabel
resRdfsResource = Res rdfsResource

-- | @rdf:Statement@ from <http://www.w3.org/TR/rdf-schema/#ch_statement>.
resRdfStatement :: RDFLabel
resRdfStatement = Res rdfStatement

-- | @rdf:subject@ from <http://www.w3.org/TR/rdf-schema/#ch_subject>.
resRdfSubject :: RDFLabel
resRdfSubject = Res rdfSubject

-- | @rdf:predicate@ from <http://www.w3.org/TR/rdf-schema/#ch_predicate>.
resRdfPredicate :: RDFLabel
resRdfPredicate = Res rdfPredicate

-- | @rdf:object@ from <http://www.w3.org/TR/rdf-schema/#ch_object>.
resRdfObject :: RDFLabel
resRdfObject = Res rdfObject

-- | @rdf:RDF@.
resRdfRDF :: RDFLabel
resRdfRDF = Res rdfRDF

-- | @rdf:Description@.
resRdfDescription :: RDFLabel
resRdfDescription = Res rdfDescription

-- | @rdf:ID@.
resRdfID :: RDFLabel
resRdfID = Res rdfID

-- | @rdf:about@.
resRdfAbout :: RDFLabel
resRdfAbout = Res rdfAbout

-- | @rdf:parseType@.
resRdfParseType :: RDFLabel
resRdfParseType = Res rdfParseType

-- | @rdf:resource@.
resRdfResource :: RDFLabel
resRdfResource = Res rdfResource

-- | @rdf:li@.
resRdfLi :: RDFLabel
resRdfLi = Res rdfLi

-- | @rdf:nodeID@.
resRdfNodeID :: RDFLabel
resRdfNodeID = Res rdfNodeID

-- | @rdf:datatype@.
resRdfDatatype :: RDFLabel
resRdfDatatype = Res rdfDatatype

-- | @rdf:_1@.
resRdf1 :: RDFLabel
resRdf1 = Res rdf1

-- | @rdf:_2@.
resRdf2 :: RDFLabel
resRdf2 = Res rdf2

-- | Create a @rdf:_n@ entity.
resRdfn :: Int -> RDFLabel
resRdfn = Res . rdfn

---------------------------------------------------------
--  Additional functions on RDFLabel values
---------------------------------------------------------

-- |Test if supplied labal is a URI resource node
isUri :: RDFLabel -> Bool
isUri (Res _) = True
isUri  _      = False

-- |Test if supplied labal is a literal node
-- ('Lit', 'LangLit', or 'TypedLit').
isLiteral :: RDFLabel -> Bool
isLiteral (Lit _)        = True
isLiteral (LangLit _ _)  = True
isLiteral (TypedLit _ _) = True
isLiteral  _             = False

-- |Test if supplied labal is an untyped literal node (either
-- 'Lit' or 'LangLit').
isUntypedLiteral :: RDFLabel -> Bool
isUntypedLiteral (Lit _)       = True
isUntypedLiteral (LangLit _ _) = True
isUntypedLiteral  _            = False

-- |Test if supplied labal is a typed literal node ('TypedLit').
isTypedLiteral :: RDFLabel -> Bool
isTypedLiteral (TypedLit _ _) = True
isTypedLiteral  _             = False

-- |Test if supplied labal is a XML literal node
isXMLLiteral :: RDFLabel -> Bool
isXMLLiteral = isDatatyped rdfXMLLiteral

-- |Test if supplied label is a typed literal node of a given datatype
isDatatyped :: ScopedName -> RDFLabel -> Bool
isDatatyped d  (TypedLit _ dt) = d == dt
isDatatyped _  _               = False

-- |Test if supplied label is a container membership property
--
--  Check for namespace is RDF namespace and
--  first character of local name is '_' and
--  remaining characters of local name are all digits
isMemberProp :: RDFLabel -> Bool
isMemberProp (Res sn) =
  getScopeNamespace sn == namespaceRDF &&
  case T.uncons (getScopeLocal sn) of
    Just ('_', t) -> T.all isDigit t
    _ -> False
isMemberProp _        = False

-- |Test if supplied labal is a blank node
isBlank :: RDFLabel -> Bool
isBlank (Blank _) = True
isBlank  _        = False

-- |Test if supplied labal is a query variable
isQueryVar :: RDFLabel -> Bool
isQueryVar (Var _) = True
isQueryVar  _      = False

-- |Extract text value from a literal node (including the
-- Language and Typed variants). The empty string is returned
-- for other nodes.
getLiteralText :: RDFLabel -> T.Text
getLiteralText (Lit s)        = s
getLiteralText (LangLit s _)  = s
getLiteralText (TypedLit s _) = s
getLiteralText  _             = ""

-- |Extract the ScopedName value from a resource node ('nullScopedName'
-- is returned for non-resource nodes).
getScopedName :: RDFLabel -> ScopedName
getScopedName (Res sn) = sn
getScopedName  _       = nullScopedName

-- |Make a blank node from a supplied query variable,
--  or return the supplied label unchanged.
--  (Use this in when substituting an existential for an
--  unsubstituted query variable.)
makeBlank :: RDFLabel -> RDFLabel
makeBlank  (Var loc)    = Blank loc
makeBlank  lb           = lb

-- | RDF Triple (statement)
-- 
--   At present there is no check or type-level
--   constraint that stops the subject or
--   predicate of the triple from being a literal.
--
type RDFTriple = Arc RDFLabel

-- | Convert 3 RDF labels to a RDF triple.
--
--   See also @Swish.RDF.GraphClass.arcFromTriple@.
toRDFTriple :: 
  (ToRDFLabel s, ToRDFLabel p, ToRDFLabel o) 
  => s -- ^ Subject 
  -> p -- ^ Predicate
  -> o -- ^ Object
  -> RDFTriple
toRDFTriple s p o = 
  Arc (toRDFLabel s) (toRDFLabel p) (toRDFLabel o)

-- | Extract the contents of a RDF triple.
--
--   See also @Swish.RDF.GraphClass.arcToTriple@.
fromRDFTriple :: 
  (FromRDFLabel s, FromRDFLabel p, FromRDFLabel o) 
  => RDFTriple 
  -> Maybe (s, p, o) -- ^ The conversion only succeeds if all three
                     --   components can be converted to the correct
                     --   Haskell types.
fromRDFTriple (Arc s p o) = 
  (,,) <$> fromRDFLabel s <*> fromRDFLabel p <*> fromRDFLabel o
  
-- | Namespace prefix list entry

-- | A 'LookupMap' for name spaces.
type NamespaceMap = LookupMap Namespace

-- | A 'LookupMap' for 'reversed' name spaces.
type RevNamespaceMap = LookupMap RevNamespace

-- | Support for 'reversed' name spaces in a 'LookupMap'.
data RevNamespace = RevNamespace Namespace

instance LookupEntryClass RevNamespace URI (Maybe T.Text) where
    keyVal   (RevNamespace ns) = swap $ getNamespaceTuple ns
    newEntry (uri,pre) = RevNamespace (makeNamespace pre uri)

-- | Create an empty namespace map.
emptyNamespaceMap :: NamespaceMap
emptyNamespaceMap = LookupMap []

-- | Graph formula entry

data LookupFormula lb gr = Formula
    { formLabel :: lb -- ^ The label for the formula
    , formGraph :: gr -- ^ The contents of the formula
    }

instance (Eq lb, Eq gr) => Eq (LookupFormula lb gr) where
    f1 == f2 = formLabel f1 == formLabel f2 &&
               formGraph f1 == formGraph f2

instance (Label lb)
    => LookupEntryClass (LookupFormula lb (NSGraph lb)) lb (NSGraph lb)
    where
        keyVal fe      = (formLabel fe, formGraph fe)
        newEntry (k,v) = Formula { formLabel=k, formGraph=v }

instance (Label lb) => Show (LookupFormula lb (NSGraph lb))
    where
        show (Formula l g) = show l ++ " :- { " ++ showArcs "    " g ++ " }"

-- | A named formula.
type Formula lb = LookupFormula lb (NSGraph lb)

-- | A 'LookupMap' for named formulae.
type FormulaMap lb = LookupMap (LookupFormula lb (NSGraph lb))

-- | Create an empty formula map.
emptyFormulaMap :: FormulaMap RDFLabel
emptyFormulaMap = LookupMap []

{-  given up on trying to do Functor for formulae...
instance Functor (LookupFormula (NSGraph lb)) where
    fmap f fm = mapTranslateEntries (mapFormulaEntry f) fm
-}

formulaeMap :: (lb -> l2) -> FormulaMap lb -> FormulaMap l2
formulaeMap f = fmap (formulaEntryMap f) 

formulaEntryMap ::
    (lb -> l2)
    -> Formula lb
    -> Formula l2
formulaEntryMap f (Formula k gr) = Formula (f k) (fmap f gr)

formulaeMapA :: Applicative f => (lb -> f l2) -> 
                FormulaMap lb -> f (FormulaMap l2)
formulaeMapA f = Traversable.traverse (formulaEntryMapA f)

formulaEntryMapA ::
  (Applicative f) => 
  (lb -> f l2)
  -> Formula lb
  -> f (Formula l2)
formulaEntryMapA f (Formula k gr) = Formula `liftA` f k <*> Traversable.traverse f gr

{-
formulaeMapM ::
    (Monad m) => (lb -> m l2) -> FormulaMap lb -> m (FormulaMap l2)
formulaeMapM f = T.mapM (formulaEntryMapM f)

formulaEntryMapM ::
    (Monad m)
    => (lb -> m l2)
    -> Formula lb
    -> m (Formula l2)
formulaEntryMapM f (Formula k gr) =
  Formula `liftM` f k `ap` T.mapM f gr
    
-}

{-|

Memory-based graph with namespaces and subgraphs.

The primary means for adding arcs to an existing graph
are: 

 - `setArcs` from the `LDGraph` instance, which replaces the 
    existing set of arcs and does not change the namespace 
    map.

 - `addArc` which checks that the arc is unknown before
    adding it but does not change the namespace map or
    re-label any blank nodes in the arc.

-}
data NSGraph lb = NSGraph
    { namespaces :: NamespaceMap    -- ^ the namespaces to use
    , formulae   :: FormulaMap lb   -- ^ any associated formulae (a.k.a. sub- or named- graps)
    , statements :: [Arc lb]        -- ^ the statements in the graph
    }

instance (Label lb) => Monoid (NSGraph lb) where
  mempty = NSGraph emptyNamespaceMap (LookupMap []) []
  mappend = merge
  
instance (Label lb) => LDGraph NSGraph lb where
    getArcs      = statements 
    setArcs as g = g { statements=as }

instance Functor NSGraph where
  fmap f (NSGraph ns fml stmts) =
    NSGraph ns (formulaeMap f fml) ((map $ fmap f) stmts)

instance Foldable.Foldable NSGraph where
  foldMap = Traversable.foldMapDefault

instance Traversable.Traversable NSGraph where
  traverse f (NSGraph ns fml stmts) = 
    NSGraph ns <$> formulaeMapA f fml <*> (Traversable.traverse $ Traversable.traverse f) stmts
  
instance (Label lb) => Eq (NSGraph lb) where
    (==) = grEq

instance (Label lb) => Show (NSGraph lb) where
    show     = grShow ""
    showList = grShowList ""

-- | Retrieve the namespace map in the graph.
getNamespaces :: NSGraph lb -> NamespaceMap
getNamespaces = namespaces

-- | Replace the namespace information in the graph.
setNamespaces      :: NamespaceMap -> NSGraph lb -> NSGraph lb
setNamespaces ns g = g { namespaces=ns }

-- | Retrieve the formulae in the graph.
getFormulae :: NSGraph lb -> FormulaMap lb
getFormulae = formulae

-- | Replace the formulae in the graph.
setFormulae      :: FormulaMap lb -> NSGraph lb -> NSGraph lb
setFormulae fs g = g { formulae=fs }

-- | Find a formula in the graph, if it exists.
getFormula     :: (Label lb) => NSGraph lb -> lb -> Maybe (NSGraph lb)
getFormula g l = mapFindMaybe l (formulae g)

-- | Add (or replace) a formula.
setFormula     :: (Label lb) => Formula lb -> NSGraph lb -> NSGraph lb
setFormula f g = g { formulae=mapReplaceOrAdd f (formulae g) }

{-|
Add an arc to the graph. It does not relabel any blank nodes in the input arc,
nor does it change the namespace map, 
but it does ensure that the arc is unknown before adding it.
-}
addArc :: (Label lb) => Arc lb -> NSGraph lb -> NSGraph lb
addArc ar gr = gr { statements=addSetElem ar (statements gr) }

-- |Add element to the set.

addSetElem :: (Eq a) => a -> [a] -> [a]
addSetElem e es = if e `elem` es then es else e:es

grShowList :: (Label lb) => String -> [NSGraph lb] -> String -> String
grShowList _ []     = showString "[no graphs]"
grShowList p (g:gs) = showChar '[' . showString (grShow pp g) . showl gs
    where
        showl []     = showChar ']' -- showString $ "\n" ++ p ++ "]"
        showl (h:hs) = showString (",\n "++p++grShow pp h) . showl hs
        pp           = ' ':p

grShow   :: (Label lb) => String -> NSGraph lb -> String
grShow p g =
    "Graph, formulae: " ++ showForm ++ "\n" ++
    p ++ "arcs: " ++ showArcs p g
    where
        showForm = foldr ((++) . (pp ++) . show) "" fml
        fml = listLookupMap (getFormulae g)
        pp = "\n    " ++ p

showArcs :: (Label lb) => String -> NSGraph lb -> String
showArcs p g = foldr ((++) . (pp ++) . show) "" (getArcs g)
    where
        pp = "\n    " ++ p

-- | Graph equality.
grEq :: (Label lb) => NSGraph lb -> NSGraph lb -> Bool
grEq g1 = fst . grMatchMap g1

-- | Match graphs, returning `True` if they are equivalent,
-- with a map of labels to equivalence class identifiers
-- (see 'graphMatch' for further details).
grMatchMap :: (Label lb) =>
    NSGraph lb -> NSGraph lb -> (Bool, LabelMap (ScopedLabel lb))
grMatchMap g1 g2 =
    graphMatch matchable (getArcs g1) (getArcs g2)
    where
        matchable l1 l2 = mapFormula g1 l1 == mapFormula g2 l2
        mapFormula g l  = mapFindMaybe l (getFormulae g)

-- |Merge RDF graphs, renaming blank and query variable nodes as
--  needed to neep variable nodes from the two graphs distinct in
--  the resulting graph.
--        
--  Currently formulae are not guaranteed to be preserved across a
--  merge.
--        
merge :: (Label lb) => NSGraph lb -> NSGraph lb -> NSGraph lb
merge gr1 gr2 =
    let
        bn1   = allLabels labelIsVar gr1
        bn2   = allLabels labelIsVar gr2
        dupbn = intersect bn1 bn2
        allbn = union bn1 bn2
    in
        add gr1 (remapLabels dupbn allbn id gr2)

-- |Return list of all labels (including properties) in the graph
--  satisfying a supplied filter predicate. This routine
--  includes the labels in any formulae.
allLabels :: (Label lb) => (lb -> Bool) -> NSGraph lb -> [lb]
allLabels p gr = filter p (unionNodes p (formulaNodes p gr) (labels gr) ) 
                 
{- TODO: is the leading 'filter p' needed in allLabels?
-}

-- |Return list of all subjects and objects in the graph
--  satisfying a supplied filter predicate.
allNodes :: (Label lb) => (lb -> Bool) -> NSGraph lb -> [lb]
allNodes p = unionNodes p [] . nodes

-- | List all nodes in graph formulae satisfying a supplied predicate
formulaNodes :: (Label lb) => (lb -> Bool) -> NSGraph lb -> [lb]
formulaNodes p gr = foldl' (unionNodes p) fkeys (map (allLabels p) fvals)
    where
        -- fm :: (Label lb) => FormulaMap lb
        --                     LookupMap LookupFormula (NSGraph lb) lb
        fm    = formulae gr
        -- fvals :: (Label lb) => [NSGraph lb]
        fvals = mapVals fm
        -- fkeys :: (Label lb) => [lb]
        fkeys = filter p $ mapKeys fm

-- | Helper to filter variable nodes and merge with those found so far
unionNodes :: (Label lb) => (lb -> Bool) -> [lb] -> [lb] -> [lb]
unionNodes p ls1 ls2 = ls1 `union` filter p ls2

-- |Remap selected nodes in graph.
--
--  This is the node renaming operation that prevents graph-scoped
--  variable nodes from being merged when two graphs are merged.
remapLabels ::
    (Label lb)
    => [lb] -- ^ variable nodes to be renamed (@dupbn@)
    -> [lb] -- ^ variable nodes used that must be avoided (@allbn@)
    -> (lb -> lb) -- ^ node conversion function that is applied to nodes
    -- from @dupbn@ in the graph that are to be replaced by
    -- new blank nodes.  If no such conversion is required,
    -- supply @id@.  The function 'makeBlank' can be used to convert
    -- RDF query nodes into RDF blank nodes.
    -> NSGraph lb -- ^ graph in which nodes are to be renamed
    -> NSGraph lb
remapLabels dupbn allbn cnvbn = fmap (mapnode dupbn allbn cnvbn)

-- |Externally callable function to construct a list of (old,new)
--  values to be used for graph label remapping.
--
remapLabelList ::
    (Label lb)
    => [lb] -- ^ labels to be remaped
    -> [lb] -- ^ labels to be avoided by the remapping
    -> [(lb,lb)]
remapLabelList remap avoid = maplist remap avoid id []

-- | Remap a single graph node.
--
--  If the node is not one of those to be remapped,
--  the supplied value is returned unchanged.
mapnode ::
    (Label lb) => [lb] -> [lb] -> (lb -> lb) -> lb -> lb
mapnode dupbn allbn cnvbn nv =
    mapFind nv nv (LookupMap (maplist dupbn allbn cnvbn []))

-- | Construct a list of (oldnode,newnode) values to be used for
--  graph label remapping.  The function operates recursively, adding
--  new nodes generated to the accumulator and also to the
--  list of nodes to be avoided.
maplist ::
    (Label lb) 
    => [lb]       -- ^ oldnode values
    -> [lb]       -- ^ nodes to be avoided
    -> (lb -> lb) 
    -> [(lb,lb)]  -- ^ accumulator
    -> [(lb,lb)]
maplist []         _     _     mapbn = mapbn
maplist (dn:dupbn) allbn cnvbn mapbn = maplist dupbn allbn' cnvbn mapbn'
    where
        dnmap  = newNode (cnvbn dn) allbn
        mapbn' = (dn,dnmap):mapbn
        allbn' = dnmap:allbn

-- |Given a node and a list of existing nodes, find a new node for
--  the supplied node that does not clash with any existing node.
--  (Generates an non-terminating list of possible replacements, and
--  picks the first one that isn't already in use.)
--
--  TODO: optimize this for common case @nnn@ and @_nnn@:
--    always generate @_nnn@ and keep track of last allocated
--
newNode :: (Label lb) => lb -> [lb] -> lb
newNode dn existnodes =
    head $ newNodes dn existnodes

-- |Given a node and a list of existing nodes, generate a list of new
--  nodes for the supplied node that do not clash with any existing node.
newNodes :: (Label lb) => lb -> [lb] -> [lb]
newNodes dn existnodes =
    filter (not . (`elem` existnodes)) $ trynodes (noderootindex dn)

{- 

For now go with a 32-bit integer (since Int on my machine uses 32-bit
values). We could instead use a Whole class constraint from
Numeric.Natural (in semigroups), but it is probably better to
specialize here. The idea for using Word<X> rather than Int is to
make it obvious that we are only interested in values >= 0.

-}

noderootindex :: (Label lb) => lb -> (String, Word32)
noderootindex dn = (nh,nx) where
    (nh,nt) = splitnodeid $ getLocal dn
    nx      = if null nt then 0 else read nt

splitnodeid :: String -> (String,String)
splitnodeid = break isDigit

trynodes :: (Label lb) => (String, Word32) -> [lb]
trynodes (nr,nx) = [ makeLabel (nr++show n) | n <- iterate (+1) nx ]

{-
trybnodes :: (Label lb) => (String,Int) -> [lb]
trybnodes (nr,nx) = [ makeLabel (nr++show n) | n <- iterate (+1) nx ]
-}

-- | Memory-based RDF graph type

type RDFGraph = NSGraph RDFLabel

-- |Create a new RDF graph from a supplied list of arcs
--
-- This version will attempt to fill up the namespace map
-- of the graph based on the input labels (including datatypes
-- on literals). For faster
-- creation of a graph you can use:
--
-- > emptyRDFGraph { statements = arcs }
--
-- which is how this routine was defined in version @0.3.1.1@
-- and earlier.
--
toRDFGraph :: [RDFTriple] -> RDFGraph
-- toRDFGraph arcs = emptyRDFGraph { statements = arcs }
toRDFGraph arcs = 
  let lbls = concatMap arcLabels arcs
      
      getNS (Res s) = Just s
      getNS (TypedLit _ dt) = Just dt
      getNS _ = Nothing

      ns = mapMaybe (fmap getScopeNamespace . getNS) lbls
      nsmap = foldl' mapAddIfNew emptyNamespaceMap ns
  
  in mempty { namespaces = nsmap, statements = arcs }

-- |Create a new, empty RDF graph.
--
-- This uses `mempty` from the `Monoid` instance
-- of `NSGraph`.
--
emptyRDFGraph :: RDFGraph
emptyRDFGraph = mempty 

{-
-- |Update an RDF graph using a supplied list of arcs, keeping
--  prefix definitions and formula definitions from the original.
--
--  [[[TODO:  I think this may be redundant - the default graph
--  class has an update method which accepts a function to update
--  the arcs, not touching other parts of the graph value.]]]
updateRDFGraph :: RDFGraph -> [RDFTriple] -> RDFGraph
updateRDFGraph gr as = gr { statements=as }
-}

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
