--------------------------------------------------------------------------------
--  See end of this file for licence information.
--------------------------------------------------------------------------------
-- |
--  Module      :  RDFParser
--  Copyright   :  (c) 2003, Graham Klyne, 2009 Vasili I Galchin, 2011 Douglas Burke
--  License     :  GPL V2
--
--  Maintainer  :  Douglas Burke
--  Stability   :  provisional
--  Portability :  H98
--
--  Support for the RDF Parsing modules.
--
--------------------------------------------------------------------------------

module Swish.HaskellRDF.RDFParser
    ( SpecialMap
    , mapPrefix
              
    -- tables
    , prefixTable, specialTable

    -- parser
    , ParseResult, RDFParser
    , n3Style, n3Lexer
    , annotateParsecError
    , mkTypedLit
    )
where

import Swish.HaskellRDF.RDFGraph
    ( RDFGraph, RDFLabel(..)
    , NamespaceMap
    )

import Swish.HaskellUtils.LookupMap
    ( LookupMap(..)
    , mapFind 
    )

import Swish.HaskellUtils.Namespace
    ( Namespace(..)
    , ScopedName(..)
    )

import Swish.HaskellRDF.Vocabulary
    ( namespaceRDF
    , namespaceRDFS
    , namespaceRDFD
    , namespaceOWL
    , namespaceLOG
    , rdf_type
    , rdf_first, rdf_rest, rdf_nil
    , owl_sameAs, log_implies
    , default_base
    )

import Swish.HaskellUtils.ErrorM (ErrorM)

import Control.Applicative
import Control.Monad (MonadPlus(..), ap)

import Text.ParserCombinators.Parsec (GenParser, ParseError, char, letter, alphaNum, errorPos, sourceLine, sourceColumn)
import Text.ParserCombinators.Parsec.Error (errorMessages, showErrorMessages)
import Text.ParserCombinators.Parsec.Language (emptyDef)
import qualified Text.ParserCombinators.Parsec.Token as P

-- Code

{-|
The language definition for N3-style formats.
-}

n3Style :: P.LanguageDef st
n3Style =
        emptyDef
            { P.commentStart   = ""
            , P.commentEnd     = ""
            , P.commentLine    = "#"
            , P.nestedComments = True
            , P.identStart     = letter <|> char '_'      -- oneOf "_"
            , P.identLetter    = alphaNum <|> char '_'
            , P.reservedNames  = []
            , P.reservedOpNames= []
            , P.caseSensitive  = True
            }

{-|
The lexer for N3 style languages.
-}
n3Lexer :: P.TokenParser st
n3Lexer = P.makeTokenParser n3Style

-- | Type for special name lookup table
type SpecialMap = LookupMap (String,ScopedName)

-- | Lookup prefix in table and return URI or 'prefix:'
mapPrefix :: NamespaceMap -> String -> String
mapPrefix ps pre = mapFind (pre++":") pre ps

--  Define default table of namespaces
prefixTable :: [Namespace]
prefixTable =   [ namespaceRDF
                , namespaceRDFS
                , namespaceRDFD     -- datatypes
                , namespaceOWL
                , namespaceLOG
                ]

--  Define default special-URI table
specialTable :: [(String,ScopedName)]
specialTable =  [ ( "a",         rdf_type       ),
                  ( "equals",    owl_sameAs     ),
                  ( "implies",   log_implies    ),
                  ( "listfirst", rdf_first      ),
                  ( "listrest",  rdf_rest       ),
                  ( "listnull",  rdf_nil        ),
                  ( "base",      default_base   ) ]

----------------------------------------------------------------------
--  Define top-level parser function:
--  accepts a string and returns a graph or error
----------------------------------------------------------------------

type RDFParser a b = GenParser Char a b

-- Applicative/Alternative are defined for us in Parsec 3
instance Applicative (GenParser a b) where
  pure = return
  (<*>) = ap
  
instance Alternative (GenParser a b) where
  empty = mzero
  (<|>) = mplus
  
type ParseResult = ErrorM RDFGraph

-- | Annotate a Parsec error with the local context (i.e. the actual text
-- that caused the error.
--
annotateParsecError :: 
    [String] -- ^ text being parsed
    -> ParseError -- ^ the parse error
    -> String -- ^ Parsec error with additional context
annotateParsecError ls err = 
    -- the following is based on the show instance of ParseError
    let ePos = errorPos err
        lNum = sourceLine ePos
        cNum = sourceColumn ePos
        -- it is possible to be at the end of the input so need
        -- to check; should produce better output than this in this
        -- case
        lTxt = if lNum > length ls then "" else ls !! (lNum - 1)
        indicator = replicate (cNum-1) ' ' ++ "^"
        eHdr = ["", lTxt, indicator, "(line " ++ show lNum ++ ", column " ++ show cNum ++ " indicated by the '^' sign above):"]
        eMsg = showErrorMessages "or" "unknown parse error" "expecting" "unexpected" "end of input"
               (errorMessages err)

    in unlines eHdr ++ eMsg

-- | Create a typed literal.
mkTypedLit ::
  ScopedName -- ^ the type
  -> String -- ^ the value
  -> RDFLabel
mkTypedLit u v = Lit v (Just u)

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
