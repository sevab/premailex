defmodule Premailex.HTMLParser.FlokiTest do
  use ExUnit.Case
  doctest Premailex.HTMLParser.Floki

  alias Premailex.HTMLParser.Floki

  describe "parse/1" do
    test "with document" do
      assert Floki.parse("""
             <html>
               <body>
                 <p>Hi</p>
               </body>
             </html>
             """) ==
               [
                 {"html", [],
                  [
                    "\n  ",
                    {"body", [], ["\n    ", {"p", [], ["Hi"]}, "\n  "]},
                    "\n"
                  ]}
               ]
    end

    test "with document fragment" do
      assert Floki.parse("<p>Hi</p>") == [{"p", [], ["Hi"]}]

      assert Floki.parse("<h1>Hi</h1> <p>there</p>") ==
               [{"h1", [], ["Hi"]}, " ", {"p", [], ["there"]}]
    end
  end

  test "to_html/1" do
    assert Floki.to_html([{"html", [], [{"body", [], [{"p", [], ["Hi"]}]}]}]) ==
             "<html><body><p>Hi</p></body></html>"
  end
end
