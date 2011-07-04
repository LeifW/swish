--------------------------------------------------------------------------------
--  See end of this file for licence information.
--------------------------------------------------------------------------------
-- |
--  Module      :  N3Parser
--  Copyright   :  (c) 2003, Graham Klyne, 2009 Vasili I Galchin, 2011 Douglas Burke
--  License     :  GPL V2
--
--  Maintainer  :  Douglas Burke
--  Stability   :  experimental
--  Portability :  H98
--
--  This Module implements a Notation 3 parser (see [1], [2], [3]), returning a
--  new 'RDFGraph' consisting of triples and namespace information parsed from
--  the supplied N3 input string, or an error indication.
--
-- REFERENCES:
--
-- 1 <http://www.w3.org/TeamSubmission/2008/SUBM-n3-20080114/>
--     Notation3 (N3): A readable RDF syntax,
--     W3C Team Submission 14 January 2008
--
-- 2 <http://www.w3.org/DesignIssues/Notation3.html>
--     Tim Berners-Lee's design issues series notes and description
--
-- 3 <http://www.w3.org/2000/10/swap/Primer.html>
--     Notation 3 Primer by Sean Palmer
--
-- NOTES:
--
--  UTF-8 handling is not really tested.
--
--  No performance testing has been applied.
--
--  Not all N3 grammar elements are supported, including:
--
--    - @\@forSome@ (we read it in but ignore the arguments)
--
--    - @\@forAll@  (this causes a parse error)
--
--    - formulae are lightly tested
--
--    - string support is incomplete (e.g. unrecognized escape characters
--      such as @\\q@ are probably handled incorrectly)
--
--------------------------------------------------------------------------------

module Swish.RDF.N3Parser
    ( ParseResult
    , parseN3      
    , parseN3fromString
    , parseAnyfromString
    , parseAnyfromText
    , parseTextFromString, parseAltFromString
    , parseNameFromString, parsePrefixFromString
    , parseAbsURIrefFromString, parseLexURIrefFromString, parseURIref2FromString
    
    -- * Exports for parsers that embed Notation3 in a bigger syntax
    , N3Parser, N3State(..), SpecialMap
    
    , getPrefix -- a combination of the old defaultPrefix and namedPrefix productions
    , n3symbol -- replacement for uriRef2 -- TODO: check this is semantically correct      
    , quickVariable -- was varid      
    , lexUriRef       
    , document, subgraph                                                   
    , newBlankNode
    )
where

import Swish.RDF.RDFGraph
    ( RDFGraph, RDFLabel(..)
    , ToRDFLabel(..)
    , NamespaceMap
    , LookupFormula(..) 
    , addArc 
    , setFormula
    , setNamespaces
    , emptyRDFGraph
    )

import Swish.RDF.GraphClass (arc)

import Swish.Utils.LookupMap
    ( LookupMap(..)
    , LookupEntryClass(..)
    , mapFind, mapFindMaybe, mapReplaceOrAdd, mapAdd, mapReplace )

import Swish.Utils.Namespace
    ( Namespace(..)
    , ScopedName(..)
    , getScopedNameURI
    , makeScopedName, makeUriScopedName
    , makeQNameScopedName
    , nullScopedName
    )

import Swish.Utils.QName (QName, getQNameURI)

import Swish.RDF.Vocabulary
    ( langName
    , rdf_type
    , rdf_first, rdf_rest, rdf_nil
    , owl_sameAs, log_implies
    , xsd_boolean, xsd_integer, xsd_decimal, xsd_double
    )

import Swish.RDF.RDFParser
    ( SpecialMap
    , ParseResult
    , mapPrefix
    , prefixTable
    , specialTable
    , ignore
    , notFollowedBy
    , endBy
    , sepEndBy
    , manyTill
    , noneOf
    , char
    , ichar
    , string
    , symbol
    , lexeme
    , whiteSpace
    , mkTypedLit
    , hex4  
    , hex8  
    )

import Control.Applicative
import Control.Monad (forM_, foldM)

import Network.URI (URI, 
                    relativeTo,
                    parseURI, parseURIReference, uriToString)

import Data.Char (isSpace, isDigit, chr) 
import Data.Maybe (fromMaybe, fromJust)

import qualified Data.Text as T
import qualified Data.Text.Lazy as L
import Text.ParserCombinators.Poly.StateText

----------------------------------------------------------------------
-- Define parser state and helper functions
----------------------------------------------------------------------

-- | N3 parser state
data N3State = N3State
        { graphState :: RDFGraph            -- Graph under construction
        , thisNode   :: RDFLabel            -- current context node (aka 'this')
        , prefixUris :: NamespaceMap        -- namespace prefix mapping table
        , syntaxUris :: SpecialMap          -- special name mapping table
        , nodeGen    :: Int                 -- blank node id generator
        , keywordsList :: [String]          -- contents of the @keywords statement
        , allowLocalNames :: Bool           -- True if @keywords used so that bare names are QNames in default namespace
        }

-- | Functions to update N3State vector (use with stUpdate)
setPrefix :: String -> String -> N3State -> N3State
setPrefix pre uri st =  st { prefixUris=p' }
    where
        p' = mapReplaceOrAdd (Namespace pre uri) (prefixUris st)

-- | Set name for special syntax element
setSName :: String -> ScopedName -> N3State -> N3State
setSName nam snam st =  st { syntaxUris=s' }
    where
        s' = mapReplaceOrAdd (nam,snam) (syntaxUris st)

setSUri :: String -> String -> N3State -> N3State
setSUri nam suri = setSName nam (makeScopedName "" suri "")

-- | Set the list of tokens that can be used without needing the leading 
-- \@ symbol.
setKeywordsList :: [String] -> N3State -> N3State
setKeywordsList ks st = st { keywordsList = ks, allowLocalNames = True }

--  Functions to access state:

-- | Get name for special syntax element, default null
getSName :: N3State -> String -> ScopedName
getSName st nam =  mapFind nullScopedName nam (syntaxUris st)

getSUri :: N3State -> String -> String
getSUri st nam = getScopedNameURI $ getSName st nam

--  Map prefix to namespace
getPrefixNs :: N3State -> String -> Namespace
getPrefixNs st pre = Namespace pre (mapPrefix (prefixUris st) pre)

getKeywordsList :: N3State -> [String]
getKeywordsList = keywordsList

getAllowLocalNames :: N3State -> Bool
getAllowLocalNames = allowLocalNames

--  Return function to update graph in N3 parser state,
--  using the supplied function of a graph
--
updateGraph :: (RDFGraph -> RDFGraph) -> N3State -> N3State
updateGraph f s = s { graphState = f (graphState s) }

----------------------------------------------------------------------
--  Define top-level parser function:
--  accepts a string and returns a graph or error
----------------------------------------------------------------------

type N3Parser a = Parser N3State a

-- | Parse a string as N3 (with no real base URI).
-- 
-- See 'parseN3' if you need to provide a base URI.
--
parseN3fromString ::
  String -- ^ input in N3 format.
  -> ParseResult
parseN3fromString txt = parseN3 (L.pack txt) Nothing

-- | Parse a string with an optional base URI.
--            
-- See also 'parseN3fromString'.            
--
parseN3 ::
  L.Text -- ^ input in N3 format.
  -> Maybe QName -- ^ optional base URI
  -> ParseResult
parseN3 txt mbase = parseAnyfromText document mbase txt

{-
-- useful for testing
test :: String -> RDFGraph
test = either error id . parseAnyfromString document Nothing
-}

-- | Function to supply initial context and parse supplied term.
--
parseAnyfromString :: N3Parser a      -- ^ parser to apply
                      -> Maybe QName  -- ^ base URI of the input, or @Nothing@ to use default base value
                      -> String       -- ^ input to be parsed
                      -> Either String a
parseAnyfromString p mb = parseAnyfromText p mb . L.pack

-- | Function to supply initial context and parse supplied term.
--
parseAnyfromText :: N3Parser a      -- ^ parser to apply
                    -> Maybe QName  -- ^ base URI of the input, or @Nothing@ to use default base value
                    -> L.Text       -- ^ input to be parsed
                    -> Either String a
parseAnyfromText parser mbase input =
  let pmap   = LookupMap []
      muri   = fmap makeQNameScopedName mbase
      smap   = LookupMap $ specialTable muri
      pstate = N3State
              { graphState = emptyRDFGraph
              , thisNode   = NoNode
              , prefixUris = pmap
              , syntaxUris = smap
              , nodeGen    = 0
              , keywordsList = ["a", "is", "of", "true", "false"] -- not 100% sure about true/false here
              , allowLocalNames = False
              }
  
      puri = case mbase of
        Just base -> fmap showURI $ appendUris (getQNameURI base) "#"
        _ -> Right "#"

      -- this is getting a bit ugly
        
  in case puri of
    Left emsg -> Left $ "Invalid base: " ++ emsg
    Right p -> let (result, _, _) = runParser parser (setPrefix "" p pstate) input
               in result

newBlankNode :: N3Parser RDFLabel
newBlankNode = do
  n <- stQuery (succ . nodeGen)
  stUpdate $ \s -> s { nodeGen = n }
  return $ Blank (show n)
  
--  Test functions for selected element parsing

-- TODO: remove these
  
parseTextFromString :: String -> String -> Either String String
parseTextFromString s =
    parseAnyfromString (string s) Nothing

parseAltFromString :: String -> String -> String -> Either String String
parseAltFromString s1 s2 =
    parseAnyfromString (string s1 <|> string s2) Nothing

parseNameFromString :: String -> Either String String
parseNameFromString =
    parseAnyfromString n3Name Nothing

{-
This has been made tricky by the attempt to remove the default list
of prefixes from the starting point of a N3 parse and the subsequent
attempt to add every new namespace we come across to the parser state.

So we add in the original default namespaces for testing, since
this routine is really for testing.
-}

addTestPrefixes :: N3Parser ()
addTestPrefixes = stUpdate $ \st -> st { prefixUris = LookupMap prefixTable } -- should append to existing map

parsePrefixFromString :: String -> Either String Namespace
parsePrefixFromString =
    parseAnyfromString p Nothing
      where
        p = do
          addTestPrefixes
          pref <- n3Name
          st   <- stGet
          return (getPrefixNs st pref)   -- map prefix to namespace

parseAbsURIrefFromString :: String -> Either String String
parseAbsURIrefFromString =
    parseAnyfromString (fmap showURI explicitURI) Nothing

parseLexURIrefFromString :: String -> Either String String
parseLexURIrefFromString =
    parseAnyfromString lexUriRef Nothing

parseURIref2FromString :: String -> Either String ScopedName
parseURIref2FromString = 
    parseAnyfromString (addTestPrefixes *> n3symbol) Nothing

----------------------------------------------------------------------
--  Syntax productions
----------------------------------------------------------------------

-- helper routines

comma, semiColon , fullStop :: N3Parser ()
comma = ignore $ symbol ","
semiColon = ignore $ symbol ";"
fullStop = ignore $ symbol "."

-- a specialization of bracket/between 
br :: String -> String -> N3Parser a -> N3Parser a
br lsym rsym = bracket (symbol lsym) (symbol rsym)

-- to make porting from parsec to polyparse easier
between :: Parser s lbr -> Parser s rbr -> Parser s a -> Parser s a
between = bracket

-- The @ character is optional if the keyword is in the
-- keyword list
--
atSign :: String -> N3Parser ()
atSign s = do
  st <- stGet
  
  let p = ichar '@'
  
  if s `elem` getKeywordsList st
    then ignore $ optional p
    else p
         
atWord :: String -> N3Parser String
atWord s = do
  atSign s
  
  -- TODO: does it really make sense to add the not-followed-by-a-colon rule here?
  -- apply to both cases even though should only really be necessary
  -- when the at sign is not given
  --
  lexeme $ string s *> notFollowedBy (== ':')
  return s

showURI :: URI -> String
showURI u = uriToString id u ""

-- TODO: look at using URIs throughout
getScopedNameURI' :: URI -> String
getScopedNameURI' = showURI
-- getScopedNameURI' = getScopedNameURI . makeUriScopedName . showURI

{-
Since operatorLabel can be used to add a label with an 
unknown namespace, we need to ensure that the namespace
is added if not known. If the namespace prefix is already
in use then it is over-written (rather than add a new
prefix for the label).

TODO:
  - could we use the reverse lookupmap functionality to
    find if the given namespace URI is in the namespace
    list? If it is, use it's key otherwise do a
    mapReplaceOrAdd for the input namespace.
    
-}
operatorLabel :: ScopedName -> N3Parser RDFLabel
operatorLabel snam@(ScopedName sns _) = do
  st <- stGet
  let opmap = prefixUris st
      pkey = entryKey sns
      pval = entryVal sns
      
      rval = Res snam
      
  -- the lookup and the replacement could be fused
  case mapFindMaybe pkey opmap of
    Just val | val == pval -> return rval
             | otherwise   -> do
               stUpdate $ \s -> s { prefixUris = mapReplace opmap sns }
               return rval
    
    _ -> do
      stUpdate $ \s -> s { prefixUris = mapAdd opmap sns }
      return rval
        
{-
Add statement to graph in N3 parser state.

To support literals that are written directly/implicitly - i.e.  as
true/false/1/1.0/1.0e23 - rather than a string with an explicit
datatype we need to special case handling of the object label for
literals. Is this actually needed? The N3 Formatter now doesn't
display the xsd: datatypes on output, but there may be issues with
other formats (e.g RDF/XML once it is supported).

-}

type AddStatement = RDFLabel -> N3Parser ()

addStatement :: RDFLabel -> RDFLabel -> AddStatement
addStatement s p o@(Lit _ (Just dtype)) | dtype `elem` [xsd_boolean, xsd_integer, xsd_decimal, xsd_double] = do 
  ost <- stGet
  let stmt = arc s p o
      oldp = prefixUris ost
      ogs = graphState ost
      newp = mapReplaceOrAdd (snScope dtype) oldp
  stUpdate $ \st -> st { prefixUris = newp, graphState = addArc stmt ogs }
addStatement s p o = stUpdate (updateGraph (addArc (arc s p o) ))

addStatementRev :: RDFLabel -> RDFLabel -> AddStatement
addStatementRev o p s = addStatement s p o

{-
A number of productions require a name, which starts with

[A-Z_a-z#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x02ff#x0370-#x037d#x037f-#x1fff#x200c-#x200d#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff]

and then has

[\-0-9A-Z_a-z#x00b7#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x037d#x037f-#x1fff#x200c-#x200d#x203f-#x2040#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff]*

we encode this as the n3Name production
-}

initChar , bodyChar :: String
initChar =
  ['A'..'Z'] ++ "_" ++ ['a'..'z'] ++
  map chr 
  ([0x00c0..0x00d6] ++ [0x00d8..0x00f6] ++ [0x00f8..0x02ff] ++ [0x0370..0x037d] ++ [0x037f..0x1fff] ++ [0x200c..0x200d] ++ [0x2070..0x218f] ++ [0x2c00..0x2fef] ++ [0x3001..0xd7ff] ++ [0xf900..0xfdcf] ++ [0xfdf0..0xfffd] ++ [0x00010000..0x000effff])
bodyChar = 
  '-' : ['0'..'9'] ++ ['A'..'Z'] ++ "_" ++ ['a'..'z'] ++
  map chr
  (0x00b7 : [0x00c0..0x00d6] ++ [0x00d8..0x00f6] ++ [0x00f8..0x037d] ++ [0x037f..0x1fff] ++ [0x200c..0x200d] ++ [0x203f..0x2040] ++ [0x2070..0x218f] ++ [0x2c00..0x2fef] ++ [0x3001..0xd7ff] ++ [0xf900..0xfdcf] ++ [0xfdf0..0xfffd] ++ [0x00010000..0x000effff])

n3Name :: N3Parser String
n3Name = (:) <$> n3Init <*> n3Body
  where
    n3Init = satisfy (`elem` initChar)
    n3Body = L.unpack <$> manySatisfy (`elem` bodyChar)

{-
quickvariable ::=	\?[A-Z_a-z#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x02ff#x0370-#x037d#x037f-#x1fff#x200c-#x200d#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff][\-0-9A-Z_a-z#x00b7#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x037d#x037f-#x1fff#x200c-#x200d#x203f-#x2040#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff]*
-}

-- TODO: is mapping to Var correct?
quickVariable :: N3Parser RDFLabel
quickVariable = char '?' *> (Var <$> n3Name) 

{-
string ::=	("""[^"\\]*(?:(?:\\.|"(?!""))[^"\\]*)*""")|("[^"\\]*(?:\\.[^"\\]*)*")

or

string ::= tripleQuoted | singleQUoted

-}

n3string :: N3Parser String
n3string = tripleQuoted <|> singleQuoted 

{-
singleQuoted ::=  "[^"\\]*(?:\\.[^"\\]*)*"

asciiChars :: String
asciiChars = map chr [0x20..0x7e]

asciiCharsN3 :: String
asciiCharsN3 = filter (`notElem` "\\\"") asciiChars

-}

digit :: N3Parser Char
digit = satisfy isDigit

{-
This is very similar to NTriples accept that also allow the escaping of '
even though it is not required.

The Python rules allow \N{name}, where name is the Unicode name. It's
not clear whether we need to support this too, so for now we do not.

-}
protectedChar :: N3Parser Char
protectedChar =
  (char 't' *> return '\t')
  <|> (char 'n' *> return '\n')
  <|> (char 'r' *> return '\r')
  <|> (char '"' *> return '"')
  <|> (char '\'' *> return '\'')
  <|> (char '\\' *> return '\\')
  <|> (char 'u' *> hex4)
  <|> (char 'U' *> hex8)

-- Accept an escape character or any character as long as it isn't
-- a new-line or quote. Unrecognized escape sequences should therefore
-- be left alone by this. 
--
n3Character :: N3Parser Char
n3Character = 
  (char '\\' *> (protectedChar <|> return '\\'))
  <|> noneOf "\"\n"
      
{-
      <|> (oneOf asciiCharsN3 <?> "ASCII character")
              -- TODO: bodyChar and asciiCharsN3 overlap
      <|> (oneOf bodyChar <?> "Unicode character")
-}              

sQuot :: N3Parser Char
sQuot = char '"'

-- NOTE: changed from parsec between to polyparse bracket; is
-- there a semantic difference?
singleQuoted :: N3Parser String
singleQuoted = bracket sQuot sQuot $ many n3Character
    
{-
tripleQUoted ::=	"""[^"\\]*(?:(?:\\.|"(?!""))[^"\\]*)*"""
-}
tripleQuoted :: N3Parser String
tripleQuoted = tQuot *> manyTill (n3Character <|> sQuot <|> char '\n') tQuot
  where
    -- tQuot = try (count 3 sQuot)
    tQuot = exactly 3 sQuot

getDefaultPrefix :: N3Parser Namespace
getDefaultPrefix = do
  s <- stGet
  return (getPrefixNs s "")

addBase :: URI -> N3Parser ()
addBase = stUpdate . setSUri "base" . getScopedNameURI'

addPrefix :: Maybe String -> URI -> N3Parser ()
addPrefix p = stUpdate . setPrefix (fromMaybe "" p) . getScopedNameURI'

{-|
Update the set of keywords that can be given without
an \@ sign.
-}
updateKeywordsList :: [String] -> N3Parser ()
updateKeywordsList = stUpdate . setKeywordsList

{-
document ::=		|	statements_optional EOF
-}

document :: N3Parser RDFGraph
document = mkGr <$> (whiteSpace *> statementsOptional *> eof *> stGet)
  where
    mkGr s = setNamespaces (prefixUris s) (graphState s)

{-
statements_optional ::=		|	statement  "."  statements_optional
		|	void

-}

statementsOptional :: N3Parser ()
statementsOptional = ignore $ endBy (lexeme statement) fullStop
    
{-
statement ::=		|	declaration
		|	existential
		|	simpleStatement
		|	universal

-}

statement :: N3Parser ()
statement =
  declaration
  <|> existential
  <|> universal
  <|> simpleStatement
  -- having an error here leads to less informative errors in general, it seems
  -- <?> "statement (existential or universal quantification or a simple statement)"
  
{-
declaration ::=		|	 "@base"  explicituri
		|	 "@keywords"  barename_csl
		|	 "@prefix"  prefix explicituri
-}

-- TODO: do we need the try statements here? atWord would need to have a try on '@'
-- (if applicable) which should mean being able to get rid of try
--
declaration :: N3Parser ()
declaration = oneOf [
  atWord "base" >> explicitURI >>= addBase,
  atWord "keywords" >> bareNameCsl >>= updateKeywordsList,
  atWord "prefix" *> getPrefix
  ]

  {-
  (try (atWord "base") >> explicitURI >>= addBase)
  <|>
  (try (atWord "keywords") >> bareNameCsl >>= updateKeywordsList)
  <|>
  (try (atWord "prefix") *> getPrefix)
  -}
  
getPrefix :: N3Parser ()  
getPrefix = do
  p <- lexeme prefix
  u <- explicitURI
  addPrefix p u

{-
explicituri ::=	<[^>]*>

Note: white space is to be ignored within <>
-}

explicitURI :: N3Parser URI
explicitURI = do
  let lb = char '<'
      rb = char '>'
  
  -- TODO: do the whitespace definitions match?
  ustr <- between lb rb $ many (satisfy (/= '>'))
  let uclean = filter (not . isSpace) ustr
      
  s <- stGet
  let base = getSUri s "base"
      
  case appendUris base uclean of 
    Right uri -> return uri
    Left emsg -> fail emsg
      
appendUris :: String -> String -> Either String URI
appendUris base uri =
  case parseURI uri of
    Just absuri -> Right absuri
    _ -> case parseURIReference uri of
      Just reluri -> 
        let baseuri = fromJust $ parseURI base
        in case relativeTo reluri baseuri of
          Just resuri -> Right resuri
          _ -> Left $ "Unable to append <" ++ uri ++ "> to base=<" ++ base ++ ">"
          
      _ -> Left $ "Invalid URI: <" ++ uri ++ ">"
      
-- production from the old parser
lexUriRef :: N3Parser String
lexUriRef = fmap showURI $ lexeme explicitURI

{-
barename ::=	[A-Z_a-z#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x02ff#x0370-#x037d#x037f-#x1fff#x200c-#x200d#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff][\-0-9A-Z_a-z#x00b7#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x037d#x037f-#x1fff#x200c-#x200d#x203f-#x2040#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff]*
barename_csl ::=		|	barename barename_csl_tail
		|	void
barename_csl_tail ::=		|	 ","  barename barename_csl_tail
		|	void
-}

bareNameCsl :: N3Parser [String]
bareNameCsl = sepBy (lexeme bareName) comma

bareName :: N3Parser String
bareName = n3Name 

{-
prefix ::=	([A-Z_a-z#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x02ff#x0370-#x037d#x037f-#x1fff#x200c-#x200d#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff][\-0-9A-Z_a-z#x00b7#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x037d#x037f-#x1fff#x200c-#x200d#x203f-#x2040#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff]*)?:
-}

prefix :: N3Parser (Maybe String)
prefix = optional (lexeme n3Name) <* char ':'
         

{-
symbol ::=		|	explicituri
		|	qname
symbol_csl ::=		|	symbol symbol_csl_tail
		|	void
symbol_csl_tail ::=		|	 ","  symbol symbol_csl_tail
		|	void

-}

n3symbol :: N3Parser ScopedName
n3symbol = 
  ((makeUriScopedName . showURI) <$> explicitURI)
  <|> qname

symbolCsl :: N3Parser [ScopedName]
symbolCsl = sepBy (lexeme n3symbol) comma

{-
qname ::=	(([A-Z_a-z#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x02ff#x0370-#x037d#x037f-#x1fff#x200c-#x200d#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff][\-0-9A-Z_a-z#x00b7#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x037d#x037f-#x1fff#x200c-#x200d#x203f-#x2040#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff]*)?:)?[A-Z_a-z#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x02ff#x0370-#x037d#x037f-#x1fff#x200c-#x200d#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff][\-0-9A-Z_a-z#x00b7#x00c0-#x00d6#x00d8-#x00f6#x00f8-#x037d#x037f-#x1fff#x200c-#x200d#x203f-#x2040#x2070-#x218f#x2c00-#x2fef#x3001-#xd7ff#xf900-#xfdcf#xfdf0-#xfffd#x00010000-#x000effff]*

TODO:
  Note that, for now, we explicitly handle blank nodes
  (of the form _:name) direcly in pathItem'.
  This is not a good idea since qname' is used elsewhere
  and so shouldn't we do the same thing there too?
-}

qname :: N3Parser ScopedName
qname =
  (char ':' *> toSN getDefaultPrefix)
  <|> (n3Name >>= fullOrLocalQName)
    where
      toSN p = ScopedName <$> p <*> (n3Name <|> return "")
          
fullOrLocalQName :: String -> N3Parser ScopedName
fullOrLocalQName name = 
  (char ':' *> fullQName name)
  <|> localQName name
  
fullQName :: String -> N3Parser ScopedName
fullQName name = do
  pre <- findPrefix name
  lname <- n3Name <|> return ""
  return $ ScopedName pre lname
  
findPrefix :: String -> N3Parser Namespace
findPrefix pre = do
  st <- stGet
  case mapFindMaybe pre (prefixUris st) of
    Just uri -> return $ Namespace pre uri
    Nothing  -> failBad $ "Prefix '" ++ pre ++ ":' not bound."
  
localQName :: String -> N3Parser ScopedName
localQName name = do
  st <- stGet
  if getAllowLocalNames st
    then ScopedName <$> getDefaultPrefix <*> pure name
    else fail "Invalid 'bare' word" -- TODO: not ideal error message; can we handle this case differently?

{-
existential ::=		|	 "@forSome"  symbol_csl

For now we just read in the symbols and ignore them,
since we do not mark blank nodes as existentially quantified
(we assume this is the case).

TODO: fix this?
-}

existential :: N3Parser ()
-- existential = try (atWord "forSome") *> symbolCsl >> return ()
existential = atWord "forSome" *> symbolCsl *> pure ()

{-
simpleStatement ::=		|	subject propertylist
-}

simpleStatement :: N3Parser ()
simpleStatement = subject >>= propertyListWith
  
{-
subject ::=		|	expression
-}

subject :: N3Parser RDFLabel
subject = lexeme expression

{-
expression ::=		|	pathitem pathtail
pathtail ::=		|	 "!"  expression
		|	 "^"  expression
		|	void

-}

expression :: N3Parser RDFLabel
expression = do
  i <- pathItem
  
  let backwardExpr = char '!' *> return addStatementRev 
      forwardExpr  = char '^' *> return addStatement
  
  mpt <- optional
        ( (,) <$> lexeme (forwardExpr <|> backwardExpr) <*> lexeme expression )
  case mpt of
    Nothing -> return i 
    Just (addFunc, pt) -> do
      bNode <- newBlankNode
      addFunc bNode pt i
      return bNode
  
{-
pathitem ::=		|	 "("  pathlist  ")" 
		|	 "["  propertylist  "]" 
		|	 "{"  formulacontent  "}" 
		|	boolean
		|	literal
		|	numericliteral
		|	quickvariable
		|	symbol

pathlist ::=		|	expression pathlist
		|	void

Need to think about how to handle formulae, since need to know the context
of the call to know where to add them.

TOOD: may include direct support for blank nodes here,
namely convert _:stringval -> Blank stringval since although
this should be done by symbol the types don't seem to easily match
up (at first blush anyway)
-}

pathItem :: N3Parser RDFLabel
pathItem = 
  br "(" ")" pathList
  <|> br "[" "]" propertyListBNode
  <|> br "{" "}" formulaContent
  -- <|> try boolean
  <|> boolean
  <|> literal
  <|> numericLiteral
  <|> quickVariable
  <|> Blank <$> (string "_:" *> n3Name) -- TODO a hack that needs fixing
  <|> Res <$> n3symbol
  
{-  
we create a blank node for the list and return it, whilst
adding the list contents to the graph
-}
pathList :: N3Parser RDFLabel
pathList = do
  cts <- many (lexeme expression)
  eNode <- operatorLabel rdf_nil
  case cts of
    [] -> return eNode
      
    (c:cs) -> do
      sNode <- newBlankNode
      first <- operatorLabel rdf_first
      addStatement sNode first c
      lNode <- foldM addElem sNode cs
      rest <- operatorLabel rdf_rest
      addStatement lNode rest eNode
      return sNode

    where      
      addElem prevNode curElem = do
        bNode <- newBlankNode
        first <- operatorLabel rdf_first
        rest <- operatorLabel rdf_rest
        addStatement prevNode rest bNode
        addStatement bNode first curElem
        return bNode
        
{-
formulacontent ::=		|	statementlist

statementlist ::=		|	statement statementtail
		|	void
statementtail ::=		|	 "."  statementlist
		|	void
-}

restoreState :: N3State -> N3Parser N3State
restoreState origState = do
  oldState <- stGet
  stUpdate $ \_ -> origState { nodeGen = nodeGen oldState }
  return oldState

{-
We create a subgraph and assign it to a blank node, returning the
blank node. At present it is a combination of the subgraph and formula
productions from the origial parser.

TODO: is it correct?
-}
formulaContent :: N3Parser RDFLabel
formulaContent = do
  bNode <- newBlankNode
  pstate <- stGet
  stUpdate $ \st -> st { graphState = emptyRDFGraph, thisNode = bNode }
  statementList
  oldState <- restoreState pstate
  stUpdate $ updateGraph $ setFormula (Formula bNode (graphState oldState))
  return bNode
  
subgraph :: RDFLabel -> N3Parser RDFGraph
subgraph this = do
  pstate <- stGet
  stUpdate $ \st -> st { graphState = emptyRDFGraph, thisNode = this }
  statementsOptional    -- parse statements of formula
  oldState <- restoreState pstate  
  return $ graphState oldState
  
statementList :: N3Parser ()
statementList = ignore $ sepEndBy (lexeme statement) fullStop

{-
boolean ::=		|	 "@false" 
		|	 "@true" 
-}

boolean :: N3Parser RDFLabel
boolean = mkTypedLit xsd_boolean <$> 
          (atWord "false" <|> atWord "true")
          -- (try (atWord "false") <|> atWord "true")
           
{-
dtlang ::=		|	 "@"  langcode
		|	 "^^"  symbol
		|	void
literal ::=		|	string dtlang

langcode ::=	[a-z]+(-[a-z0-9]+)*

-}

literal :: N3Parser RDFLabel
literal = Lit <$> (T.pack <$> n3string) <*> optional dtlang
  
dtlang :: N3Parser ScopedName
dtlang = 
  (char '@' *> langcode)
  <|> string "^^" *> n3symbol
  -- <|> (try (string "^^") *> n3symbol)

langcode :: N3Parser ScopedName
langcode = do
  h <- many1Satisfy (`elem` ['a'..'z'])
  mt <- optional ( L.append <$> (char '-' *> pure (L.singleton '-')) <*> many1Satisfy (`elem` ['a'..'z'] ++ ['0'..'9']))
  return $ langName $ L.unpack $ L.append h (fromMaybe L.empty mt)
    
{-
decimal ::=	[-+]?[0-9]+(\.[0-9]+)?
double ::=	[-+]?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)
integer ::=	[-+]?[0-9]+
numericliteral ::=		|	decimal
		|	double
		|	integer

TODO: we could convert via something like

  maybeRead value :: Double >>= Just . toRDFLabel

which would mean we store the canonical XSD value in the
label, but it is not useful for the xsd:decimal case
since we currently don't have a Haskell type that
goes with it.
-}

numericLiteral :: N3Parser RDFLabel
numericLiteral =
  -- -- try (mkTypedLit xsd_double <$> n3double)
  -- try (d2s <$> n3double)
  -- <|> try (mkTypedLit xsd_decimal <$> n3decimal)
  d2s <$> n3double
  <|> mkTypedLit xsd_decimal <$> n3decimal
  <|> mkTypedLit xsd_integer <$> n3integer

n3sign :: N3Parser Char
n3sign = char '+' <|> char '-'

n3integer :: N3Parser String
n3integer = do
  ms <- optional n3sign
  ds <- many1 digit
  case ms of
    Just s -> return $ s : ds
    _ -> return ds

n3decimal :: N3Parser String
n3decimal = (++) <$> n3integer <*> ( (:) <$> char '.' <*> many1 digit )
           
n3double :: N3Parser String  
n3double = (++) <$> n3decimal <*> ( (:) <$> satisfy (`elem` "eE") <*> n3integer )

-- convert a double, as returned by n3double, into it's
-- canonical XSD form
d2s :: String -> RDFLabel
d2s s = toRDFLabel (read s :: Double)

{-
propertylist ::=		|	verb object objecttail propertylisttail
		|	void
propertylisttail ::=		|	 ";"  propertylist
		|	void

-}

-- it's probably important that bNode is created *after*
-- processing the plist (mainly for the assumptions made by
-- formatting the output as N3; e.g. list/sequence ordering)
--
propertyListBNode :: N3Parser RDFLabel
propertyListBNode = do
  plist <- sepEndBy ((,) <$> lexeme verb <*> objectList) semiColon
  bNode <- newBlankNode
  let addList ((addFunc,vrb),items) = mapM_ (addFunc bNode vrb) items
  forM_ plist addList
  return bNode

propertyListWith :: RDFLabel -> N3Parser ()
propertyListWith subj = 
  let -- term = lexeme verb >>= objectListWith subj
      term = lexeme verb >>= \(addFunc, vrb) -> objectListWith (addFunc subj vrb)
  in ignore $ sepEndBy term semiColon
  
{-
object ::=		|	expression
objecttail ::=		|	 ","  object objecttail
		|	void

We change the production rule from objecttail to objectlist for lists of
objects (may change back).

May be an optimisation needed in the case of

 :s :p :o1 , .. , :o<large number>.

Is parsec creating the list of actions, using sepBy1
in objectListWith, and then evaluating them all once the list
has been created?

-}

object :: N3Parser RDFLabel
object = lexeme expression

objectList :: N3Parser [RDFLabel]
objectList = sepBy1 object comma

objectWith :: AddStatement -> N3Parser ()
objectWith addFunc = object >>= addFunc 

objectListWith :: AddStatement -> N3Parser ()
objectListWith addFunc =
  ignore $ sepBy1 (objectWith addFunc) comma

{-
objectList1 :: N3Parser [RDFLabel]
objectList1 = sepBy1 object comma
-}

{-
verb ::=		|	 "<=" 
		|	 "=" 
		|	 "=>" 
		|	 "@a" 
		|	 "@has"  expression
		|	 "@is"  expression  "@of" 
		|	expression

-}

verb :: N3Parser (RDFLabel -> RDFLabel -> AddStatement, RDFLabel)
verb = 
  -- we check reverse first so that <= is tried before looking for a URI via expression rule
  (,) addStatementRev <$> verbReverse
  <|> (,) addStatement <$> verbForward

-- those verbs for which subject is on the right and object on the left
verbReverse :: N3Parser RDFLabel
verbReverse =
  string "<=" *> operatorLabel log_implies
  <|> between (atWord "is") (atWord "of") (lexeme expression)

{-
  try (string "<=") *> operatorLabel log_implies
  <|> between (try (atWord "is")) (atWord "of") (lexeme expression)
-}

-- those verbs with subject on the left and object on the right
verbForward :: N3Parser RDFLabel
verbForward =  
  -- (try (string "=>") *> operatorLabel log_implies)
  (string "=>" *> operatorLabel log_implies)
  <|> (string "=" *> operatorLabel owl_sameAs)
  -- <|> (try (atWord "a") *> operatorLabel rdf_type)
  <|> (atWord "a" *> operatorLabel rdf_type)
  <|> (atWord "has" *> lexeme expression)
  <|> lexeme expression

{-
universal ::=		|	 "@forAll"  symbol_csl

TODO: what needs to be done to support universal quantification
-}
universal :: N3Parser ()
universal = 
  -- try (atWord "forAll") *> 
  atWord "forAll" *> 
  failBad "universal (@forAll) currently unsupported." 
  -- will be something like: *> symbolCsl

{-

-- OLD --
  
-- helper routines

isymbol :: String -> N3Parser ()
isymbol s = symbol s >> return ()

--  document         = directive* statement-list

document :: N3Parser RDFGraph
document = do
  whiteSpace
  _ <- many directive
  statements
  eof
  s <- getState
  return $ setNamespaces (prefixUris s) (graphState s)
    
--  directive        = "@prefix" prefix ":" uriRef2 "."   // Namespace declaration
--                   | "@prefix" ":" uriRef2 "."          // Default namespace
--                   | "@equivalence" uriRef2 "."         // Alternative to daml:equivalent
--                   | "@listfirst" uriRef2 "."           // Alternative to n3:first
--                   | "@listrest"  uriRef2 "."           // Alternative to n3:rest
--                   | "@listnull"  uriRef2 "."           // Alternative to n3:null
--                   | "@plus"  uriRef2 "."               // Alternative to operator:plus
--                   | "@minus" uriRef2 "."               // Alternative to operator:minus
--                   | "@slash" uriRef2 "."               // Alternative to operator:slash
--                   | "@star"  uriRef2 "."               // Alternative to operator:star
--                   | "@base"  uriRef2 "."               // Base URI for relative URIs.

directive :: N3Parser ()
directive = 
  (try (symbol "@prefix") >> (defaultPrefix <|> namedPrefix))
  <|> (string "@" >> syntaxUri)
  <?> "directive"

defaultPrefix :: N3Parser ()
defaultPrefix = do
  u <- br ":" "." uriRef2
  updateState $ setPrefix "" (getScopedNameURI u)

namedPrefix :: N3Parser ()
namedPrefix = do
  n <- name
  u <- br ":" "." uriRef2
  updateState $ setPrefix n (getScopedNameURI u)
        
syntaxUri :: N3Parser ()
syntaxUri = do
  s <- uriName
  u <- uriRef2
  isymbol "."
  updateState $ setSUri s (getScopedNameURI u)
        
uriName :: N3Parser String
uriName =
  try (symbol "equivalence")
  <|> try (symbol "listfirst")
  <|> try (symbol "listrest")
  <|> try (symbol "listnull")
  <|> try (symbol "plus")
  <|> try (symbol "minus")
  <|> try (symbol "slash")
  <|> try (symbol "star")
  <|> try (symbol "base")
  <?> "special URI directive"


--  statements       = [ statement ( "." statement )* ]
--
--  statement        = subject property-list
--
--  properties       = [ property ( ";" property )* ]
--
--  New statements are added to the user state graph

statements :: N3Parser ()
statements = sepEndBy1 statement (symbol ".") >> return ()

statement :: N3Parser ()
-- statement = subject >>= optional . properties  -- when using Parsec's optional
statement = subject >>= optional . properties >> return () -- not sure this is exactly the same as with Parsec

properties :: RDFLabel -> N3Parser ()
properties subj = sepBy1 (property subj) (symbol ";") >> return ()


--  property         = verb object-list
--                   | ":-" anon-node           // Creates anon-node aongside the current node
--  verb             = ">-" prop "->"           // has 'prop' of
--                   | "<-" prop "<-"           // is  'prop' of
--                   | operator                 // has operator:'operator' of (???)
--                   | prop                     // has 'prop' of -- shorthand
--                   | "has" prop "of"          // has 'prop' of
--                   | "is" prop "of"           // is  'prop' of
--                   | "a"                      // has rdf:type of
--                   | "="                      // has daml:equivalent of
--
--  subj    is the subject node for these properties.
--
--  New statements are added to the graph in the parser's user state.

property :: RDFLabel -> N3Parser ()
property subj =
  (verb >>= uncurry (objects subj))
  <|>
  (isymbol ":-" >> anonNode subj >> return ())

verb :: N3Parser (RDFLabel,Bool)
verb = 
  (prop >>= \p -> return (p, False))    
  <|> (operator >>= \p -> return (p, False))
  <|> (br ">-"  "->" prop >>= \p -> return (p, False))
  <|> (br "<-"  "<-" prop >>= \p -> return (p, True))
  <|> (br "has" "of" prop >>= \p -> return (p, False))
  <|> (br "is"  "of" prop >>= \p -> return (p, True))
  <|> (symbol "a" >> operatorLabel rdf_type   >>= \lab -> return (lab, False))
  <|> (symbol "=" >> operatorLabel owl_sameAs >>= \lab -> return (lab, False))
  <?> "property"


--  objects          = object
--                   | object "," object-list
--
--  subj    is the subject node for the new statements,
--  prop    is the property node for the new statements.
--  swap    is true if the subject/object values in the resulting statement
--          are to be swapped (for "is <prop> of", etc.)
--
--  New statements are added to the graph in the parser's user state

objects :: RDFLabel -> RDFLabel -> Bool -> N3Parser ()
objects subj ppty swap = 
  sepBy1 (object subj ppty swap) (symbol ",") >> return ()

--  anonNode         = "[" property-list "]"    // Something with given properties
--                   | "{" statement-list "}"   // List of statements as resource
--                   | "(" node-list ")"        // Construct list with
--                                              //   rdf:first, rdf:rest, rdf:nil
--
--  subj    is the subject node with which the new anonymous node is equated,
--
--  The anonymous node value is returned by this parser (which is often the same
--  as the supplied subject node, but not always).
--
--  New statements are added to the graph in the parser's user state
--  (in the case of a formula, a new graph and parser are created, and
--  the graph arcs are added to this new graph).

anonNode :: RDFLabel -> N3Parser RDFLabel
anonNode subj =
  (br "[" "]" (properties subj) >> return subj)
  <|> br "{" "}" (formula subj)
  <|> br "(" ")" (nodeList subj)
  <?> "anon node (\"[\", \"(\" or \"{\")"

--  This method allows a statement list to be parsed as a subgraph
--  whose value is associated with the supplied node of the current
--  graph.

formula :: RDFLabel -> N3Parser RDFLabel
formula subj = do
  subgr <- subgraph subj
  updateState
    $ updateGraph
    $ setFormula (Formula subj subgr)
  return subj

subgraph :: RDFLabel -> N3Parser RDFGraph
subgraph this = do
  pstate <- getState
  let fstate = pstate { graphState = emptyRDFGraph, thisNode = this }
  setState fstate       -- switch new state into parser
  statements            -- parse statements of formula
  fstate' <- getState
  let nstate = pstate { nodeGen = nodeGen fstate' }
  setState nstate       -- swap back state, with updated nodeGen
  return (graphState fstate')

--  prop             = uri-ref2
--                   | varid
--
--  Returns URI value as a Node

prop :: N3Parser RDFLabel
prop = nodeid <|> varid <|> uriNode


--  operator         = "+"                      // >- operator:plus ->
--                   | "-"                      // >- operator:minus ->
--                   | "/"                      // >- operator:slash ->
--                   | "*"                      // >- operator:star->
--
--  If matched, the operator is returned as a node value.

operator :: N3Parser RDFLabel
operator =
  (symbol "+" >> operatorLabel operator_plus)
  <|> (symbol "-" >> operatorLabel operator_minus)
  <|> (symbol "*" >> operatorLabel operator_star)
  <|> (symbol "/" >> operatorLabel operator_slash)
  <?> ""

--  subject          = node

subject :: N3Parser RDFLabel
subject = node


--  object           = litNode
--
--  This production adds a new triple to the graph state,
--  using the supplied subject and property values.
--  If swap is True, the subject and object positions are
--  swapped.

object :: RDFLabel -> RDFLabel -> Bool -> N3Parser ()
object subj ppty True = do
  o <- litNode
  addStatement o ppty subj

object subj ppty _ = do
  o <- litNode
  addStatement subj ppty o
        
--  nodeList         = litNode*
--
--  subj    is the node from which the list is linked.
--
--  Returns the supplied head of list or Nil node allocated.
--
--  Link first element of link to list head, scan rest of list,
--  and return the list head;  otherwise return a node rdf_null.
--
--  This slightly convoluted pattern is to deal with two different
--  occurrences of a list node:
--    <node> :- ( l1, l2, ... )
--      Here, <node> (the supplied subj) is the listhead.
--    <node> prop ( l1, l2, ... )
--      Here, the a new blank is supplied as subj to be the listhead.
--  In either case, if the list is non-empty, the supplied subj
--  is returned.  But if the list is empty, a rdf_null node is returned.
--  In the second case, the invoking production must use the returned
--  value.

nodeList :: RDFLabel -> N3Parser RDFLabel
nodeList subj =
  (do
      val   <- litNode
      first <- operatorLabel rdf_first
      addStatement subj first val
      nodeList1 subj
      return subj)
  <|> operatorLabel rdf_nil
  <?> "Node or ')'"

nodeList1 :: RDFLabel -> N3Parser ()
nodeList1 prev =
  (do
      val   <- litNode
      lnk   <- newBlankNode
      first <- operatorLabel rdf_first
      rest  <- operatorLabel rdf_rest
      addStatement lnk  first val
      addStatement prev rest  lnk
      nodeList1 lnk)
  <|> (do 
          nil   <- operatorLabel rdf_nil
          rest  <- operatorLabel rdf_rest
          addStatement prev rest nil)
  <?> "Node or ')'"


--  lit-node         = node
--                   | str-node [ "@" lang ] [ "^^" uriRef2 ]
--  str-node         = '"' constant-value '"'
--                   | '"""' constant value '"""'   // Including single or double occurences of
--                                                  //   quotes and/or newlines
--
--  Returns a new node value.

litNode :: N3Parser RDFLabel
litNode = 
  node
  <|> liftM2 Lit strNode litTypeOrLang
  <?> "URI, blank node or literal"

strNode :: N3Parser String
strNode =
        tripleQuoteString
    <|> singleQuoteString


litTypeOrLang :: N3Parser (Maybe ScopedName)
litTypeOrLang =
        langTag
    <|> typeUri
    <|> return Nothing
    <?> "'@tag' (language tag) or '^^name' (datatype URI)"

langTag :: N3Parser (Maybe ScopedName)
langTag =
  fmap (Just . langName) (string "@" >> name)
  <?> "'@tag' (language tag)"
                                               
typeUri :: N3Parser (Maybe ScopedName)
typeUri =
  fmap Just (string "^^" >> uriRef2)
  <?> "'^^name' (datatype URI)"

--  node             = nodeid
--                   | varid
--                   | uri-ref2
--                   | anon-node
--
--  nodeid           = "_:" name
--
--  varid            = "?" name
--
--  Returns a new node value.

node :: N3Parser RDFLabel
node =  nodeid
    <|> varid
    <|> uriNode
    <|> (newBlankNode >>= anonNode)
    <?> "URI or blank node"

--  Identified blank node in input
--
--  Note that automatically generated blank node identifiers start with
--  a digit, where input node identifiers start with a letter, so there
--  can be no clash.  Care is needed when serializing a graph to ensure
--  that future clashes are avoided.

nodeid :: N3Parser RDFLabel
-- nodeid = lexeme nodeid1
nodeid = fmap Blank (string "_:" >> name)

--  variable identifier

varid :: N3Parser RDFLabel
varid = fmap Var (string "?" >> name)

--  uriNode          = qname
--                   | "<" URI-reference ">"
--                   | "this"

uriNode :: N3Parser RDFLabel
uriNode = 
  fmap Res uriRef2
  <|> fmap thisNode (string "this" >> getState)
  <?> "URI node"


--  uriRef2          = qname
--                   | ":" local-name
--                   | "<" URI-reference ">"
--  qname            = prefix ":" local-name
--
--  prefix           = name                         // Namespace prefix
--
--  local-name       = name                         // Local name (namespace qualified)
--
--  name             = alpha alphanumeric*
--
--  alpha            = "a"-"z"
--                   | "A"-"Z"
--                   | "_"
--
--  alphanumeric     = alpha
--                   | "0"-"9"
--
--  URI-reference    = (conforming to syntax in RFC2396)
--
--  uriRef2 returns a ScopedName.

uriRef2 :: N3Parser ScopedName
uriRef2 = lexeme (try uriRef2a)
    <?> "URI or QName"

uriRef2a :: N3Parser ScopedName
uriRef2a =
  liftM2 ScopedName prefix (colon >> localname)
  <|> (colon >> liftM2 ScopedName defaultprefix localname)
  <|> fmap makeUriScopedName absUriRef
  <?> "URI or QName"

prefix :: N3Parser Namespace
prefix = do
  pref <- prefixname
  st   <- getState
  return (getPrefixNs st pref)   -- map prefix to namespace

defaultprefix :: N3Parser Namespace
defaultprefix = do
  st <- getState
  return (getPrefixNs st "")

name :: N3Parser String
name =  lexeme $ name1 identStart

prefixname :: N3Parser String
prefixname =  name1 identStart

localname :: N3Parser String
localname =  lexeme $ name1 identLetter

--  'name1' is a name without following whitespace
--  initChar is a parser for the first character
name1 :: N3Parser Char -> N3Parser String
name1 initChar =
  liftM2 (:) initChar (many identLetter)
  <?> "identifier"


----------------------------------------------------------------------
-- Lexical support
----------------------------------------------------------------------
--
-- The following code adapted from ParsecToken,
-- modified to handle different escape conventions and triple-quoted strings
--      \c
--      \uhhhh
--      \Uhhhhhhhh
--
-- Regular single-quoted string -- cannot be split over line breaks

singleQuoteString :: N3Parser String
singleQuoteString =
    lexeme
    (   between (char '"') (char '"' <?> "end of string (\")") anyStringChars
    <?> "literal string" )

anyStringChars :: CharParser st String
anyStringChars = 
  fmap (foldr (maybe id (:)) "") (many stringChar)
      
-- Triple-quoted string -- may include line breaks, '"' or '""'.
tripleQuoteString :: N3Parser String
tripleQuoteString =
    lexeme
    (fmap (foldr (++) "") $ between (try $ string "\"\"\"")
                                    (string "\"\"\"" <?> "end of string (\"\"\")")
                                    (many tripleQuoteSubstring))
    <?> "triple-quoted literal string"

-- Match non-quote substring or one or two quote characters
tripleQuoteSubstring :: N3Parser String
tripleQuoteSubstring =
        tripleQuoteSubstring1
    <|> try sqTripleQuoteSubstring1
    <|> try dqTripleQuoteSubstring1

dqTripleQuoteSubstring1 :: N3Parser String
dqTripleQuoteSubstring1 = 
  fmap ("\"\""++) $ string "\"\"" >> tripleQuoteSubstring1

sqTripleQuoteSubstring1 :: N3Parser String
sqTripleQuoteSubstring1 =
  fmap ('"':) $ char '"' >> tripleQuoteSubstring1

-- match at least one non-quote character in a triple-quoted string
tripleQuoteSubstring1 :: N3Parser String
tripleQuoteSubstring1 =
  fmap (foldr (maybe id (:)) "") $ many1 tripleQuoteStringChar

tripleQuoteStringChar :: CharParser st (Maybe Char)
tripleQuoteStringChar =
  stringChar <|> (string "\n" >> return (Just '\n'))

stringChar :: CharParser st (Maybe Char)
stringChar =
  fmap Just stringLetter
  <|> stringEscape
  <?> "string character"

stringLetter :: CharParser st Char
stringLetter    = satisfy (\c -> (c /= '"') && (c /= '\\') && (c >= '\032'))

stringEscape :: CharParser st (Maybe Char)
stringEscape =
  fmap Just $ char '\\' >> escapeCode

-- escape codes
escapeCode :: CharParser st Char
escapeCode = charEsc <|> charUCS2 <|> charUCS4 <?> "escape code"

-- \c
charEsc :: CharParser st Char
charEsc = choice (map parseEsc escMap)
        where
            parseEsc (c,code) = fmap (const code) (char c)
            escMap            = zip "nrt\\\"\'" "\n\r\t\\\"\'"

-- \uhhhh
charUCS2 :: CharParser st Char
charUCS2 =
  fmap chr $ char 'u' >> numberFW 16 hexDigit 4 0

-- \Uhhhhhhhh
charUCS4 :: CharParser st Char
charUCS4 =
  fmap chr $ char 'U' >> numberFW 16 hexDigit 8 0

-- parse fixed-width number:
numberFW :: Int -> CharParser st Char -> Int -> Int -> CharParser st Int
numberFW _    _         0     val = return val
numberFW base baseDigit width val = do
  d <- baseDigit
  numberFW base baseDigit (width-1) (val*base + digitToInt d)


----------------------------------------------------------------------
--  Parse a URI reference from the input
--  The result returned has absolute form;  relative URIs are resolved
--  relative to the current base prefix (set using "@base").
--

--  lexeme version
lexUriRef :: N3Parser String
lexUriRef = lexeme absUriRef

-- from Swish.Utils.ProcessURI
absoluteUriPart :: String -- ^ URI base
                   -> String -- ^ URI reference
                   -> String
absoluteUriPart base rel = showURI $ fromJust $ relativeTo (fromJust (parseURIReference rel)) (fromJust (parseURI base))
  
absUriRef :: N3Parser String
absUriRef = do
  u <- between (char '<') (char '>' <?> "end of URI '>'") anyUriChars
  if isURI u
    then return u
    else if isURIReference u
         then do
           s <- getState
           return $ absoluteUriPart (getSUri s "base") u
         else fail ("Invalid URI: <"++u++">")

anyUriChars :: N3Parser String
anyUriChars = many uriChar

uriChar :: N3Parser Char
uriChar =
        alphaNum
    <|> oneOf "[];?:@&=+$,-_.!~*'()%//#"
    <?> "URI character"

-}

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
