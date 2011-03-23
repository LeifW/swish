--------------------------------------------------------------------------------
--  See end of this file for licence information.
--------------------------------------------------------------------------------
-- |
--  Module      :  NTParserTest
--  Copyright   :  (c) 2003, Graham Klyne, 2009 Vasili I Galchin, 2011 Douglas Burke
--  License     :  GPL V2
--
--  Maintainer  :  Graham Klyne
--  Stability   :  provisional
--  Portability :  H98
--
--  This Module contains test cases for module NTParser.
--
--------------------------------------------------------------------------------

module Main where

import Swish.HaskellRDF.NTParser (parseNT)

import Swish.HaskellRDF.RDFGraph
  ( RDFGraph, RDFLabel(..)
    , emptyRDFGraph 
    , toRDFGraph
    )

import Swish.HaskellUtils.Namespace (makeUriScopedName)

import Swish.HaskellRDF.Vocabulary (langName, rdf_XMLLiteral)

import Swish.HaskellRDF.GraphClass (arc)

import Swish.HaskellUtils.ErrorM
    ( ErrorM(..) )

import Test.HUnit
    ( Test(TestCase,TestList)
    , assertEqual, runTestTT )

------------------------------------------------------------
--  Parser test
------------------------------------------------------------

parseTest :: String -> String -> RDFGraph -> String -> Test
parseTest lab inp gr er =
    TestList
      [ TestCase ( assertEqual ("parseTestError:"++lab) er pe )
      , TestCase ( assertEqual ("parseTestGraph:"++lab) gr pg )
      ]
    where
        (pe,pg) = case parseNT inp of
            Result g -> (noError, g)
            Error  s -> (s, emptyRDFGraph)

noError :: String
noError = ""

-- validate that the given text can be parsed
-- (but we do not check that it's contents match)
--
validateInput :: String -> String -> Test
validateInput lbl inp = 
  let pErr = case parseNT inp of
        Result _ -> noError
        Error s -> s
        
  in TestList
    [
      TestCase (assertEqual ("validateInput:"++lbl) noError pErr)
    ]


------------------------------------------------------------
--  Rather than bother with locating an external file,
--  include it directly.
--
--  This is the contents of
--    http://www.w3.org/2000/10/rdf-tests/rdfcore/ntriples/test.nt
--  retrived on 2011-03-23 11:25:46
--
------------------------------------------------------------

w3cTest :: String
w3cTest = "#\n# Copyright World Wide Web Consortium, (Massachusetts Institute of\n# Technology, Institut National de Recherche en Informatique et en\n# Automatique, Keio University).\n#\n# All Rights Reserved.\n#\n# Please see the full Copyright clause at\n# <http://www.w3.org/Consortium/Legal/copyright-software.html>\n#\n# Test file with a variety of legal N-Triples\n#\n# Dave Beckett - http://purl.org/net/dajobe/\n# \n# $Id: test.nt,v 1.7 2003/10/06 15:52:19 dbeckett2 Exp $\n# \n#####################################################################\n\n# comment lines\n  \t  \t   # comment line after whitespace\n# empty blank line, then one with spaces and tabs\n\n         \t\n<http://example.org/resource1> <http://example.org/property> <http://example.org/resource2> .\n_:anon <http://example.org/property> <http://example.org/resource2> .\n<http://example.org/resource2> <http://example.org/property> _:anon .\n# spaces and tabs throughout:\n \t <http://example.org/resource3> \t <http://example.org/property>\t <http://example.org/resource2> \t.\t \n\n# line ending with CR NL (ASCII 13, ASCII 10)\n<http://example.org/resource4> <http://example.org/property> <http://example.org/resource2> .\r\n\n# 2 statement lines separated by single CR (ASCII 10)\n<http://example.org/resource5> <http://example.org/property> <http://example.org/resource2> .\r<http://example.org/resource6> <http://example.org/property> <http://example.org/resource2> .\n\n\n# All literal escapes\n<http://example.org/resource7> <http://example.org/property> \"simple literal\" .\n<http://example.org/resource8> <http://example.org/property> \"backslash:\\\\\" .\n<http://example.org/resource9> <http://example.org/property> \"dquote:\\\"\" .\n<http://example.org/resource10> <http://example.org/property> \"newline:\\n\" .\n<http://example.org/resource11> <http://example.org/property> \"return\\r\" .\n<http://example.org/resource12> <http://example.org/property> \"tab:\\t\" .\n\n# Space is optional before final .\n<http://example.org/resource13> <http://example.org/property> <http://example.org/resource2>.\n<http://example.org/resource14> <http://example.org/property> \"x\".\n<http://example.org/resource15> <http://example.org/property> _:anon.\n\n# \\u and \\U escapes\n# latin small letter e with acute symbol \\u00E9 - 3 UTF-8 bytes #xC3 #A9\n<http://example.org/resource16> <http://example.org/property> \"\\u00E9\" .\n# Euro symbol \\u20ac  - 3 UTF-8 bytes #xE2 #x82 #xAC\n<http://example.org/resource17> <http://example.org/property> \"\\u20AC\" .\n# resource18 test removed\n# resource19 test removed\n# resource20 test removed\n\n# XML Literals as Datatyped Literals\n<http://example.org/resource21> <http://example.org/property> \"\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource22> <http://example.org/property> \" \"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource23> <http://example.org/property> \"x\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource23> <http://example.org/property> \"\\\"\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource24> <http://example.org/property> \"<a></a>\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource25> <http://example.org/property> \"a <b></b>\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource26> <http://example.org/property> \"a <b></b> c\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource26> <http://example.org/property> \"a\\n<b></b>\\nc\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n<http://example.org/resource27> <http://example.org/property> \"chat\"^^<http://www.w3.org/2000/01/rdf-schema#XMLLiteral> .\n# resource28 test removed 2003-08-03\n# resource29 test removed 2003-08-03\n\n# Plain literals with languages\n<http://example.org/resource30> <http://example.org/property> \"chat\"@fr .\n<http://example.org/resource31> <http://example.org/property> \"chat\"@en .\n\n# Typed Literals\n<http://example.org/resource32> <http://example.org/property> \"abc\"^^<http://example.org/datatype1> .\n# resource33 test removed 2003-08-03\n"  
  
------------------------------------------------------------
--  Define some common values
------------------------------------------------------------

s1, p1, p2, o1 :: RDFLabel
s1 = Res $ makeUriScopedName "urn:b#s1"
p1 = Res $ makeUriScopedName "urn:b#p1"
p2 = Res $ makeUriScopedName "http://example.com/pred2"
o1 = Res $ makeUriScopedName "urn:b#o1"

l0, l1, l2, l3 :: RDFLabel
l0 = Lit "" Nothing
l1 = Lit "l1"  Nothing
l2 = Lit "l2-'\"line1\"'\n\nl2-'\"\"line2\"\"'" Nothing
l3 = Lit "l3--\r\"'\\--\x20&--\x17A&--" Nothing

lfr, lgben, lxml1, lxml2 :: RDFLabel
lfr    = Lit "chat"          (Just $ langName "fr")
lgben  = Lit "football"      (Just $ langName "en-gb")
lxml1  = Lit "<br/>"         (Just rdf_XMLLiteral)
lxml2  = Lit "<em>chat</em>" (Just rdf_XMLLiteral)

b1 , b2 :: RDFLabel
b1 = Blank "x1"
b2 = Blank "genid23"

------------------------------------------------------------
--  Construct graphs for testing
------------------------------------------------------------

g0 :: RDFGraph
g0 = toRDFGraph []

mkGr1 :: RDFLabel -> RDFLabel -> RDFLabel -> RDFGraph
mkGr1 s p o = toRDFGraph [arc s p o]

g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11 :: RDFGraph
g1 = mkGr1 s1 p1 o1
g2 = mkGr1 s1 p1 l0
g3 = mkGr1 s1 p1 l1
g4 = mkGr1 s1 p1 l2
g5 = mkGr1 s1 p1 l3
g6 = mkGr1 s1 p1 lfr
g7 = mkGr1 s1 p1 lgben
g8 = mkGr1 s1 p1 lxml1
g9 = mkGr1 s1 p1 lxml2
g10 = mkGr1 s1 p1 b1
g11 = mkGr1 b2 p1 b1

gm1 :: RDFGraph
gm1 = toRDFGraph [arc b2 p2 b1, arc b2 p1 o1]

------------------------------------------------------------
--  Parser tests
------------------------------------------------------------

empty1, empty2, empty3, empty4, empty5 :: String

empty1 = ""
empty2 = "\n"
empty3 = "  \n  "
empty4 = "# a comment"
empty5 = "\n   # a comment\n "

eTests :: Test
eTests = TestList 
         [
           parseTest "empty1" empty1 g0 noError
         , parseTest "empty2" empty2 g0 noError
         , parseTest "empty3" empty3 g0 noError
         , parseTest "empty4" empty4 g0 noError
         , parseTest "empty5" empty5 g0 noError
         ]
         
graph1, graph2, graph3, graph4, graph5, graph6, graph7, graph8,
  graph9, graph10, graph11 :: String

graph1 = "<urn:b#s1> <urn:b#p1> <urn:b#o1>."
graph2 = "<urn:b#s1> <urn:b#p1>  \"\"."
graph3 = "<urn:b#s1> <urn:b#p1> \"l1\" . "
graph4 = "<urn:b#s1> <urn:b#p1> \"l2-'\\\"line1\\\"'\\n\\nl2-'\\\"\\\"line2\\\"\\\"'\"."
graph5 = "<urn:b#s1> <urn:b#p1>  \"l3--\\r\\\"'\\\\--\\u0020&--\\U0000017A&--\" ."
graph6 = "<urn:b#s1> <urn:b#p1> \"chat\"@fr."
graph7 = "<urn:b#s1> <urn:b#p1> \"football\"@en-gb . "
graph8 = "<urn:b#s1> <urn:b#p1> \"<br/>\"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral>."
graph9 = "<urn:b#s1> <urn:b#p1> \"<em>chat</em>\"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral>."
graph10 = "<urn:b#s1> <urn:b#p1> _:x1 . "
graph11 = "_:genid23  <urn:b#p1> _:x1 . "

graphm1, graphm1r :: String

graphm1 = "_:genid23 <urn:b#p1> <urn:b#o1> .\n\n # test \n_:genid23  <http://example.com/pred2>  _:x1 .\n\n"
graphm1r = "_:genid23 <http://example.com/pred2> _:x1.\n_:genid23  <urn:b#p1> <urn:b#o1>.\n"

gTests :: Test
gTests = TestList 
         [
           parseTest "graph1" graph1 g1 noError
         , parseTest "graph2" graph2 g2 noError
         , parseTest "graph3" graph3 g3 noError
         , parseTest "graph4" graph4 g4 noError
         , parseTest "graph5" graph5 g5 noError
         , parseTest "graph6" graph6 g6 noError
         , parseTest "graph7" graph7 g7 noError
         , parseTest "graph8" graph8 g8 noError
         , parseTest "graph9" graph9 g9 noError
         , parseTest "graph10" graph10 g10 noError
         , parseTest "graph11" graph11 g11 noError
         , parseTest "graphm1" graphm1 gm1 noError
         , parseTest "graphm1r" graphm1r gm1 noError
         ]

allTests :: Test              
allTests = 
  TestList
  [
    eTests
  , gTests
  , validateInput "W3C test" w3cTest
  ]
  
main :: IO ()  
main = runTestTT allTests >> return ()

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
