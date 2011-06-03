{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

import           Control.Monad                (guard)
import           Control.Monad.IO.Class       (liftIO)
import           Data.Char                    (chr,ord)
import           Data.String                  (fromString)
import           Data.Text                    (toLower)
import           Data.XML.Types
import           Test.HUnit                   hiding (Test)
import           Test.Hspec
import           Test.Hspec.HUnit
import           Text.XML.Enumerator.Parse    (decodeEntities)
import qualified Control.Exception            as C
import qualified Data.ByteString.Lazy.Char8   as L
import qualified Data.Map                     as Map
import qualified Text.XML.Enumerator.Document as D
import qualified Text.XML.Enumerator.Parse    as P

import Text.XML.Enumerator.Parse (decodeEntities)
import qualified Text.XML.Enumerator.Parse as P
import qualified Text.XML.Enumerator.Render as R
import qualified Text.XML.Enumerator.Cursor as Cu
import Text.XML.Enumerator.Cursor ((&/), (&//), (&.//), ($|), ($/), ($//), ($.//))
import qualified Data.Map as Map
import qualified Data.ByteString.Lazy.Char8 as L
import Control.Monad.IO.Class (liftIO)
import qualified Data.Enumerator as E
import Data.Enumerator(($$))
import qualified Data.Enumerator.List as EL
import Data.Monoid
import Data.Text(Text)
import Control.Monad.IO.Class(MonadIO)
import Control.Monad
import Control.Applicative((<$>), (<*>))
import qualified Data.Text as T

--main :: IO [Spec]
main = hspec $ descriptions $
    [ describe "XML parsing and rendering"
        [ it "is idempotent to parse and render a document" documentParseRender
        , it "has valid parser combinators" combinators
        , it "has working choose function" testChoose
        , it "has working many function" testMany
        , it "has working orE" testOrE
        ]
    , describe "XML Cursors"
        [ it "has correct parent" cursorParent
        , it "has correct ancestor" cursorAncestor
        , it "has correct orSelf" cursorOrSelf
        , it "has correct preceding" cursorPreceding
        , it "has correct following" cursorFollowing
        , it "has correct precedingSibling" cursorPrecedingSib
        , it "has correct followingSibling" cursorFollowingSib
        , it "has correct descendant" cursorDescendant
        , it "has correct check" cursorCheck
        , it "has correct check with lists" cursorPredicate
        , it "has correct checkNode" cursorCheckNode
        , it "has correct checkElement" cursorCheckElement
        , it "has correct checkName" cursorCheckName
        , it "has correct anyElement" cursorAnyElement
        , it "has correct element" cursorElement
        , it "has correct content" cursorContent
        , it "has correct attribute" cursorAttribute
        , it "has correct &* and $* operators" cursorDeep
        ]
    ]

documentParseRender =
    mapM_ go docs
  where
    go x = x @=? D.parseLBS_ (D.renderLBS x) decodeEntities
    docs =
        [ Document (Prologue [] Nothing [])
                   (Element "foo" [] [])
                   []
        , D.parseLBS_
            "<?xml version=\"1.0\"?>\n<!DOCTYPE foo>\n<foo/>"
            decodeEntities
        , D.parseLBS_
            "<?xml version=\"1.0\"?>\n<!DOCTYPE foo>\n<foo><nested>&ignore;</nested></foo>"
            decodeEntities
        , D.parseLBS_
            "<foo><![CDATA[this is some<CDATA content>]]></foo>"
            decodeEntities
        , D.parseLBS_
            "<foo bar='baz&amp;bin'/>"
            decodeEntities
        , D.parseLBS_
            "<foo><?instr this is a processing instruction?></foo>"
            decodeEntities
        , D.parseLBS_
            "<foo><!-- this is a comment --></foo>"
            decodeEntities
        ]

combinators = P.parseLBS_ input decodeEntities $ do
    P.force "need hello" $ P.tagName "hello" (P.requireAttr "world") $ \world -> do
        liftIO $ world @?= "true"
        P.force "need child1" $ P.tagNoAttr "{mynamespace}child1" $ return ()
        P.force "need child2" $ P.tagNoAttr "child2" $ return ()
        P.force "need child3" $ P.tagNoAttr "child3" $ do
            x <- P.contentMaybe
            liftIO $ x @?= Just "combine <all> &content"
  where
    input = L.concat
        [ "<?xml version='1.0'?>\n"
        , "<!DOCTYPE foo []>\n"
        , "<hello world='true'>"
        , "<?this should be ignored?>"
        , "<child1 xmlns='mynamespace'/>"
        , "<!-- this should be ignored -->"
        , "<child2>   </child2>"
        , "<child3>combine &lt;all&gt; <![CDATA[&content]]></child3>\n"
        , "</hello>"
        ]

testChoose = P.parseLBS_ input decodeEntities $ do
    P.force "need hello" $ P.tagNoAttr "hello" $ do
        x <- P.choose
            [ P.tagNoAttr "failure" $ return 1
            , P.tagNoAttr "success" $ return 2
            ]
        liftIO $ x @?= Just 2
  where
    input = L.concat
        [ "<?xml version='1.0'?>\n"
        , "<!DOCTYPE foo []>\n"
        , "<hello>"
        , "<success/>"
        , "</hello>"
        ]

testMany = P.parseLBS_ input decodeEntities $ do
    P.force "need hello" $ P.tagNoAttr "hello" $ do
        x <- P.many $ P.tagNoAttr "success" $ return ()
        liftIO $ length x @?= 5
  where
    input = L.concat
        [ "<?xml version='1.0'?>\n"
        , "<!DOCTYPE foo []>\n"
        , "<hello>"
        , "<success/>"
        , "<success/>"
        , "<success/>"
        , "<success/>"
        , "<success/>"
        , "</hello>"
        ]

testOrE = P.parseLBS_ input decodeEntities $ do
    P.force "need hello" $ P.tagNoAttr "hello" $ do
        x <- P.tagNoAttr "failure" (return 1) `P.orE`
             P.tagNoAttr "success" (return 2)
        liftIO $ x @?= Just 2
  where
    input = L.concat
        [ "<?xml version='1.0'?>\n"
        , "<!DOCTYPE foo []>\n"
        , "<hello>"
        , "<success/>"
        , "</hello>"
        ]


name :: [Cu.Cursor] -> [Text]
name [] = []
name (c:cs) = ($ name cs) $ case Cu.node c of
                              NodeElement e -> ((nameLocalName $ elementName e) :)
                              _ -> id

cursor =
    Cu.fromNode $ NodeElement e
  where
    Document _ e _ = D.parseLBS_ input decodeEntities
    input = L.concat
        [ "<foo attr=\"x\">"
        ,    "<bar1/>"
        ,    "<bar2>"
        ,       "<baz1/>"
        ,       "<baz2 attr=\"y\"/>"
        ,       "<baz3>a</baz3>"
        ,    "</bar2>"
        ,    "<bar3>"
        ,       "<bin1/>"
        ,       "b"
        ,       "<bin2/>"
        ,       "<bin3/>"
        ,    "</bar3>"
        , "</foo>"
        ]

bar2 = Cu.child cursor !! 1
baz2 = Cu.child bar2 !! 1

bar3 = Cu.child cursor !! 2
bin2 = Cu.child bar3 !! 1

cursorParent = name (Cu.parent bar2) @?= ["foo"]
cursorAncestor = name (Cu.ancestor baz2) @?= ["bar2", "foo"]
cursorOrSelf = name (Cu.orSelf Cu.ancestor baz2) @?= ["baz2", "bar2", "foo"]
cursorPreceding = do
  name (Cu.preceding baz2) @?= ["baz1", "bar1"]
  name (Cu.preceding bin2) @?= ["bin1", "baz3", "baz2", "baz1", "bar2", "bar1"]
cursorFollowing = do
  name (Cu.following baz2) @?= ["baz3", "bar3", "bin1", "bin2", "bin3"]
  name (Cu.following bar2) @?= ["bar3", "bin1", "bin2", "bin3"]
cursorPrecedingSib = name (Cu.precedingSibling baz2) @?= ["baz1"]
cursorFollowingSib = name (Cu.followingSibling baz2) @?= ["baz3"]
cursorDescendant = (name $ Cu.descendant cursor) @?= T.words "bar1 bar2 baz1 baz2 baz3 bar3 bin1 bin2 bin3"
cursorCheck = null (cursor $.// Cu.check (const False)) @?= True
cursorPredicate = (name $ cursor $.// Cu.check Cu.descendant) @?= T.words "foo bar2 baz3 bar3"
cursorCheckNode = (name $ cursor $// Cu.checkNode f) @?= T.words "bar1 bar2 bar3"
    where f (NodeElement e) = "bar" `T.isPrefixOf` nameLocalName (elementName e)
          f _               = False
cursorCheckElement = (name $ cursor $// Cu.checkElement f) @?= T.words "bar1 bar2 bar3"
    where f e = "bar" `T.isPrefixOf` nameLocalName (elementName e)
cursorCheckName = (name $ cursor $// Cu.checkName f) @?= T.words "bar1 bar2 bar3"
    where f n = "bar" `T.isPrefixOf` nameLocalName n
cursorAnyElement = (name $ cursor $// Cu.anyElement) @?= T.words "bar1 bar2 baz1 baz2 baz3 bar3 bin1 bin2 bin3"
cursorElement = (name $ cursor $// Cu.element "baz2") @?= ["baz2"]
cursorContent = do
  Cu.content cursor @?= []
  (cursor $.// Cu.content) @?= ["a", "b"]
cursorAttribute = Cu.attribute "attr" cursor @?= ["x"]
cursorDeep = do
  (Cu.element "foo" &/ Cu.element "bar2" &// Cu.attribute "attr") cursor @?= ["y"]
  (return &.// Cu.attribute "attr") cursor @?= ["x", "y"]
  (cursor $.// Cu.attribute "attr") @?= ["x", "y"]
  (cursor $/ Cu.element "bar2" &// Cu.attribute "attr") @?= ["y"]
  (cursor $/ Cu.element "bar2" &/ Cu.element "baz2" >=> Cu.attribute "attr") @?= ["y"]
  null (cursor $| Cu.element "foo") @?= False
