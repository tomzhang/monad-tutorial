module Document where

import System.Cmd
import System.Directory
import System.IO
import Data.List
import Control.Monad
import Control.Applicative
import Control.Arrow

data Config = Config {
  name :: String,
  uri :: String,
  docbookxslVersion :: String,
  artifactsUri :: String,
  distributionsUri :: String,
  standardsUri :: String,
  styleVersion :: String,
  commitMessage :: String,
  params :: [(String, String)],
  style :: String
} deriving (Eq, Show)

defaultConfig n u = Config n u "1.75.0" "http://software.tmorris.net/artifacts/" "http://software.tmorris.net/distributions/" "http://projects.tmorris.net/public/standards/artifacts/" "1.29" "Automated Versioning" [("html.stylesheet", s), ("chunk.section.depth", "3"), ("paper.type", "A4"), ("draft.watermark.image", [])] s
  where
  s = "style.css"

ps +++ cfg = let p = params cfg
             in cfg {
               params = p ++ ps
             }

build = "build/"
dist c = build ++ name c ++ "/"
release = build ++ "release/"
archive c = name c ++ ".tar.gz"
lib = build ++ "lib/"
dependencies = [("fop/0.95/build", "fop"), ("avalon-framework/4.2.0/jars", "avalon-framework-4.2.0"), ("batik-all/1.6", "batik-all-1.6"), ("commons-logging/1.0.4", "commons-logging"), ("commons-io/1.1", "commons-io-1.1"), ("xalan-j/2.7.1", "xalan"), ("xalan-j/2.7.1", "xercesImpl"), ("xalan-j/2.7.1", "xml-apis"), ("xmlgraphics-commons/1.3.1/build", "xmlgraphics-commons-1.3.1"), ("xalan-j/2.7.1", "serializer"), ("fop-hyph/1.2", "fop-hyph")]

system' k = print k >> system k

resolve c = wget `mapM_` d >> docbook >> s
  where
  d = map (\(p, f) -> artifactsUri c ++ p ++ '/' : f ++ ".jar") dependencies
  wget k = system ("wget -c --directory=" ++ lib ++ ' ' : k)
  docbook = wget (distributionsUri c ++ "/docbook-xsl/1.75.0/docbook-xsl-1.75.0.zip") >> system ("unzip -d " ++ build ++ ' ': lib ++ "docbook-xsl-1.75.0.zip")
  s = wget (standardsUri c ++ '/' : styleVersion c ++ "/document-style/style.css")


touch f = openFile f AppendMode >>= hClose
mkdir = createDirectoryIfMissing True

initialise c = do mkdir "src/docbook"
                  touch "src/docbook/index.xml"
                  mkdir "resources"
                  resolve c

cp = concat $ intersperse ":" (map ((lib ++) . (++ ".jar") . snd) dependencies)

xsltproc' c out xsl xml = "xsltproc --xinclude --nonet " ++ p (params c) ++ " --output " ++ out ++ ' ' : build ++ "docbook-xsl-" ++ docbookxslVersion c ++ '/' : xsl ++ ' ' : xml
  where
  p = concat . intersperse " " . map (\(k, v) -> "--stringparam \"" ++ k ++ "\" \"" ++ v ++ "\"")

d ==>>> k = mkdir d >> k
d ==>> k = d ==>>> system k

xsltproc c o x = dist c ==>> xsltproc' c (dist c ++ o) x "src/docbook/index.xml"
  where
  params = [("html.stylesheet", style c), ("chunk.section.depth", "3"), ("paper.type", "A4"), ("draft.watermark.image", [])]

copyStyle c d = copyFile (lib ++ "style.css") (dist c ++ d ++ "/style.css")
fo c = xsltproc c "fo/index.fo" "fo/docbook.xsl"
html c = xsltproc c "html/index.html" "html/docbook.xsl" <* copyStyle c "html"
chunkHtml c = xsltproc c "chunk-html/index.html" "html/chunk.xsl" <* copyStyle c "chunk-html"
xhtml c = xsltproc c "xhtml/index.html" "xhtml/docbook.xsl" <* copyStyle c "xhtml"
chunkXhtml c = xsltproc c "chunk-xhtml/index.html" "xhtml/chunk.xsl" <* copyStyle c "chunk-xhtml"

fop c t f = (dist c ++ t) ==>> ("java -classpath " ++ cp ++ " org.apache.fop.cli.Main -fo " ++ dist c ++ "fo/index.fo -" ++ t ++ ' ' : dist c ++ f)
pdf c = fop c "pdf" "pdf/index.pdf"
ps c = fop c "ps" "ps/index.ps"
pcl c = fop c "pcl" "pcl/index.pcl"
tiff c = fop c "tiff" "tiff/index.tiff"
png c = fop c "png" "png/index.png"
rtf c = fop c "rtf" "rtf/index.rtf"

buildAll c = mapM_ ($c) [fo, html, chunkHtml, xhtml, chunkXhtml, fo, pdf, ps, pcl, tiff, png, rtf]

clean = doesDirectoryExist build >>= flip when (removeDirectoryRecursive build)

cleanBuild c = clean >> resolve c >> buildAll c

rel c = do cleanBuild c
           let k = "tar -C " ++ build ++ " -zcf " ++ release ++ archive c ++ ' ' : name c
           mkdir release
           system k


svn c k = system' ("svn " ++ k ++ " -m \"" ++ commitMessage c ++ "\"")

version' c v = do rel c
                  let vf = "version"
                  e <- doesFileExist vf
                  v' <- if e then readFile vf else return v
                  let r = uri c
                  let s = ["import " ++ dist c ++ ' ' : r ++ "/artifacts/" ++ v',
                          "import " ++ release ++ archive c ++ ' ' : r ++ "/artifacts/" ++ v' ++ '/' : archive c,
                          "copy " ++ r ++ "/trunk/ " ++ r ++ "/tags/" ++ v']
                  mapM_ (svn c) s
                  let incv v = case second (show . (1+) . read . drop 1) (break (== '.') v) of (x, y) -> x ++ '.' : y
                  when e (writeFile vf (incv v') <* svn c ("commit " ++ vf))

version c = version' c []