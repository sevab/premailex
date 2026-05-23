defmodule Premailex.HTMLParser.MeeseeksTest do
  use ExUnit.Case
  doctest Premailex.HTMLParser.Meeseeks

  alias Premailex.HTMLParser.Meeseeks

  describe "parse/1" do
    test "with document" do
      assert Meeseeks.parse("""
             <html>
               <head>
                 <title>Page</title>
               </head>
               <body>
                 <p>Hi</p>
               </body>
             </html>
             """) == [
               {
                 "html",
                 [],
                 [
                   {"head", [], ["\n    ", {"title", [], ["Page"]}, "\n  "]},
                   "\n  ",
                   {"body", [], ["\n    ", {"p", [], ["Hi"]}, "\n  \n\n"]}
                 ]
               }
             ]

      assert Meeseeks.parse("""
             <HTML>
               <body>
                 <p>Hi</p>
               </body>
             </html>
             """) == [
               {
                 "html",
                 [],
                 [
                   {"head", [], []},
                   {"body", [], ["\n    ", {"p", [], ["Hi"]}, "\n  \n\n"]}
                 ]
               }
             ]
    end

    test "with document fragment" do
      assert Meeseeks.parse("<p>Hi</p>") == [{"p", [], ["Hi"]}]

      assert Meeseeks.parse("<h1>Hi</h1><p>there</p>") ==
               [{"h1", [], ["Hi"]}, {"p", [], ["there"]}]

      assert Meeseeks.parse("<p>Hi</p>\t<p>there</p>\t\n") == [
               {"p", [], ["Hi"]},
               "\t",
               {"p", [], ["there"]},
               "\t\n"
             ]
    end
  end

  describe "to_html/1" do
    test "with document" do
      assert Meeseeks.to_html([
               {
                 "html",
                 [],
                 [
                   "\n  ",
                   {"head", [], ["\n    ", {"title", [], ["Page"]}, "\n  "]},
                   "\n  ",
                   {"body", [], ["\n    ", {"p", [], ["Hi"]}, "\n  "]},
                   "\n"
                 ]
               }
             ]) ==
               """
               <html>
                 <head>
                   <title>Page</title>
                 </head>
                 <body>
                   <p>Hi</p>
                 </body>
               </html>\
               """
    end

    test "with document fragment" do
      assert Meeseeks.to_html([{"p", [], ["Hi"]}]) == ~s(<p>Hi</p>)

      assert Meeseeks.to_html([
               {"p", [], ["Hi"]},
               " ",
               {"p", [], ["there"]},
               "\t\n"
             ]) ==
               """
               <p>Hi</p> <p>there</p>\t
               """
    end
  end
end
