defmodule Premailex.HTMLParser.LazyHTMLTest do
  use ExUnit.Case
  doctest Premailex.HTMLParser.LazyHTML

  alias Premailex.HTMLParser.LazyHTML

  describe "parse/1" do
    test "with document" do
      assert LazyHTML.parse("""
             <html>
               <body>
                 <p>Hi</p>
               </body>
             </html>
             """) ==
               [
                 {"html", [],
                  [
                    {"head", [], []},
                    {"body", [], ["\n    ", {"p", [], ["Hi"]}, "\n  \n\n"]}
                  ]}
               ]
    end

    test "with document fragment" do
      assert LazyHTML.parse("<p>Hi</p>") == [{"p", [], ["Hi"]}]
    end
  end

  describe "to_html/1" do
    assert LazyHTML.to_html([
             {"html", [],
              [
                {"head", [], []},
                {"body", [], [{"p", [], ["Hi"]}]}
              ]}
           ]) == "<html><head></head><body><p>Hi</p></body></html>"
  end
end
