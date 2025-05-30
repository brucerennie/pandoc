{-# LANGUAGE OverloadedStrings #-}
{- |
   Module      : Text.Pandoc.Readers.Org.BlockStarts
   Copyright   : Copyright (C) 2014-2024 Albert Krewinkel
   License     : GNU GPL, version 2 or above

   Maintainer  : Albert Krewinkel <albert+pandoc@tarleb.com>

Parsers for Org-mode inline elements.
-}
module Text.Pandoc.Readers.Org.BlockStarts
  ( exampleLineStart
  , hline
  , noteMarker
  , tableStart
  , drawerStart
  , headerStart
  , metaLineStart
  , latexEnvStart
  , commentLineStart
  , bulletListStart
  , orderedListStart
  , endOfBlock
  ) where

import Control.Monad (void, guard)
import Data.Text (Text)
import Text.Pandoc.Readers.Org.Parsing
import Text.Pandoc.Definition as Pandoc
import Text.Pandoc.Shared (safeRead)
import Text.Pandoc.Parsing (lowerAlpha, upperAlpha)
import Text.Pandoc.Extensions
import Text.Pandoc.Readers.LaTeX.Math (inlineEnvironmentNames)
import Data.Functor (($>))

-- | Horizontal Line (five -- dashes or more)
hline :: Monad m => OrgParser m ()
hline = try $ do
  skipSpaces
  string "-----"
  many (char '-')
  skipSpaces
  newline
  return ()

-- | Read the start of a header line, return the header level
headerStart :: Monad m => OrgParser m Int
headerStart = try $
  (length <$> many1 (char '*')) <* many1 (char ' ') <* updateLastPreCharPos

tableStart :: Monad m => OrgParser m Char
tableStart = try $ skipSpaces *> char '|'

gridTableStart :: Monad m => OrgParser m ()
gridTableStart = try $ skipSpaces <* char '+' <* char '-'


latexEnvStart :: Monad m => OrgParser m Text
latexEnvStart = try $ do
  skipSpaces
  string "\\begin{"
  name <- latexEnvName
  char '}'
  guard $ name `notElem` inlineEnvironmentNames
  pure name
 where
   latexEnvName :: Monad m => OrgParser m Text
   latexEnvName = try $ mappend <$> many1Char alphaNum <*> option "" (textStr "*")

listCounterCookie :: Monad m => OrgParser m Int
listCounterCookie = try $
  string "[@"
  *> parseNum
  <* char ']'
  <* (skipSpaces <|> lookAhead eol)
  where parseNum = (safeRead =<< many1Char digit)
                   <|> snd <$> (lowerAlpha <|> upperAlpha)

bulletListStart :: Monad m => OrgParser m Int
bulletListStart = try $ do
  ind <- length <$> many spaceChar
   -- Unindented lists cannot use '*' bullets.
  oneOf (if ind == 0 then "+-" else "*+-")
  skipSpaces1 <|> lookAhead eol
  optionMaybe listCounterCookie
  return (ind + 1)

eol :: Monad m => OrgParser m ()
eol = void (char '\n')

orderedListStart :: Monad m => OrgParser m (Int, ListAttributes)
orderedListStart = try $ do
  ind <- length <$> many spaceChar
  fancy <- option False $ True <$ guardEnabled Ext_fancy_lists
  -- Ordered list markers allowed in org-mode
  let styles = (many1Char digit $> (if fancy
                                       then Decimal
                                       else DefaultStyle))
               : if fancy
                    then [ fst <$> lowerAlpha
                         , fst <$> upperAlpha ]
                    else []
  let delims = [ char '.' $> (if fancy
                                 then Period
                                 else DefaultDelim)
               , char ')' $> (if fancy
                                 then OneParen
                                 else DefaultDelim)
               ]
  style <- choice styles
  delim <- choice delims
  skipSpaces1 <|> lookAhead eol
  start <- option 1 listCounterCookie
  return (ind + 1, (start, style, delim))

drawerStart :: Monad m => OrgParser m Text
drawerStart = try $ skipSpaces *> drawerName <* skipSpaces <* newline
 where drawerName = char ':' *> manyTillChar nonspaceChar (char ':')

metaLineStart :: Monad m => OrgParser m ()
metaLineStart = try $ skipSpaces <* string "#+"

commentLineStart :: Monad m => OrgParser m ()
commentLineStart = try $
  -- the first char after '#' must be a plain space character or a newline
  skipSpaces <* string "#" <* lookAhead (oneOf " \n")

exampleLineStart :: Monad m => OrgParser m ()
exampleLineStart = () <$ try (skipSpaces *> char ':' *> (void (char ' ') <|> lookAhead eol))

noteMarker :: Monad m => OrgParser m Text
noteMarker = try $ do
  char '['
  choice [ many1TillChar digit (char ']')
         , (<>) <$> textStr "fn:"
                <*> many1TillChar (noneOf "\n\r\t ") (char ']')
         ]

-- | Succeeds if the parser is at the end of a block.
endOfBlock :: Monad m => OrgParser m ()
endOfBlock = lookAhead . try $
  void blankline <|> anyBlockStart
 where
   -- Succeeds if there is a new block starting at this position.
   anyBlockStart :: Monad m => OrgParser m ()
   anyBlockStart = try . choice $
     [ exampleLineStart
     , hline
     , metaLineStart
     , commentLineStart
     , gridTableStart
     , void noteMarker
     , void tableStart
     , void drawerStart
     , void headerStart
     , void latexEnvStart
     , void bulletListStart
     , void orderedListStart
     ]
