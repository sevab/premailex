defmodule Premailex.HTMLParser.XmerlTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias Premailex.HTMLParser.Xmerl

  describe "parse/1" do
    test "with empty" do
      assert Xmerl.parse("") == []
    end

    test "with doctype declaration" do
      tree = Xmerl.parse("<!DOCTYPE html><div>content</div>")

      assert tree == {"div", [], ["content"]}
    end

    test "with undeclared XML references" do
      tree = Xmerl.parse("<p>&nbsp;</p>")

      assert {"p", [], ["\u00A0"]} = tree
    end

    test "with comments" do
      tree = Xmerl.parse("<div><!--comment--></div>")

      assert {"div", [], [{:comment, "comment"}]} = tree
    end

    test "with void elements" do
      tree =
        Xmerl.parse(~s(<div><img src="/pixel" alt="pixel"/><img src='test'><br/><br></div>))

      assert {"div", [],
              [
                {"img", [{"src", "/pixel"}, {"alt", "pixel"}], []},
                {"img", [{"src", "test"}], []},
                {"br", [], []},
                {"br", [], []}
              ]} = tree
    end

    test "with malformed XML" do
      assert_raise ArgumentError, ~r/could not parse the HTML/, fn ->
        Xmerl.parse("<html><body><div><p>broken</div></body></html>")
      end
    end

    test "with namespaced elements and attributes" do
      tree =
        Xmerl.parse(
          ~s(<a xmlns="urn:test" xmlns:x="urn:x" x:href="/go"><x:child class="test">Body</x:child></a>)
        )

      assert {"a", [attr_1, attr_2, attr_3], [{"x:child", [{"class", "test"}], ["Body"]}]} = tree
      assert attr_1 == {"xmlns", "urn:test"}
      assert attr_2 == {"xmlns:x", "urn:x"}
      assert attr_3 == {"x:href", "/go"}
    end

    test "with ignorable whitespace" do
      assert Xmerl.parse("""
                 <div>   <p> </p>\t
               </div>\t
             """) == ["    ", {"div", [], ["   ", {"p", [], [" "]}, "\t\n  "]}, "\t\n"]
    end

    test "with whitespace in attribute value" do
      assert Xmerl.parse(~s(<div data-x="a\nb"></div>)) == {"div", [{"data-x", "a b"}], []}
      assert Xmerl.parse(~s(<div data-x="a\tb"></div>)) == {"div", [{"data-x", "a b"}], []}
    end

    test "with html entities" do
      assert Xmerl.parse("&copy; &nbsp; &lt;") == "\u00A9 \u00A0 <"
      assert Xmerl.parse("&unknown;") == "&unknown;"
    end

    test "with single element" do
      tree = Xmerl.parse("<span>solo</span>")

      assert tree == {"span", [], ["solo"]}
    end

    test "with multiple root elements" do
      tree = Xmerl.parse("<span>one</span><span>two</span>")

      assert tree == [{"span", [], ["one"]}, {"span", [], ["two"]}]
    end
  end

  describe "all/2" do
    setup do
      html =
        """
        <body id="main">
          <!--hidden-->
          <div class="container">
            <p class="intro featured" data-kind="primary" data-x="1">First</p>
            <p>Second</p>
            <a href="/">Link</a>
            <a href="/go" class="cta">Link</a>
          </div>
          <p>Outside div</p>
        </body>
        """

      {:ok, tree: Xmerl.parse(html)}
    end

    test "with tag selector", %{tree: tree} do
      assert Xmerl.all(tree, "p") == [
               {"p", [{"class", "intro featured"}, {"data-kind", "primary"}, {"data-x", "1"}],
                ["First"]},
               {"p", [], ["Second"]},
               {"p", [], ["Outside div"]}
             ]
    end

    test "with universal tag selector", %{tree: tree} do
      assert [{"body", [{"id", "main"}], _}, {"div", _, _} | _] = Xmerl.all(tree, "*")
    end

    test "with id selector", %{tree: tree} do
      assert [{"body", [{"id", "main"}], _}] = Xmerl.all(tree, "#main")
    end

    test "with class selector", %{tree: tree} do
      assert Xmerl.all(tree, ".cta") == [
               {"a", [{"href", "/go"}, {"class", "cta"}], ["Link"]}
             ]
    end

    test "with class selector with multiple classes", %{tree: tree} do
      assert Xmerl.all(tree, ".intro") == [
               {"p", [{"class", "intro featured"}, {"data-kind", "primary"}, {"data-x", "1"}],
                ["First"]}
             ]

      assert Xmerl.all(tree, ".featured") == [
               {"p", [{"class", "intro featured"}, {"data-kind", "primary"}, {"data-x", "1"}],
                ["First"]}
             ]

      assert Xmerl.all(tree, ".intro.featured") == [
               {"p", [{"class", "intro featured"}, {"data-kind", "primary"}, {"data-x", "1"}],
                ["First"]}
             ]

      assert Xmerl.all(tree, ".intro.absent") == []
      assert Xmerl.all(tree, ".feature") == []
      assert Xmerl.all(tree, ".intr") == []
    end

    test "with class selector with substring in the middle of class" do
      tree = Xmerl.parse(~s(<p class="my-intro-here">Mid</p>))

      assert Xmerl.all(tree, ".intro") == []
    end

    test "with attribute selector", %{tree: tree} do
      assert Xmerl.all(tree, "[href]") == [
               {"a", [{"href", "/"}], ["Link"]},
               {"a", [{"href", "/go"}, {"class", "cta"}], ["Link"]}
             ]

      assert Xmerl.all(tree, ~s(a[href="/go"])) == [
               {"a", [{"href", "/go"}, {"class", "cta"}], ["Link"]}
             ]
    end

    test "with pseudo selector", %{tree: tree} do
      assert Xmerl.all(tree, "p:first-of-type") == [
               {"p", [{"class", "intro featured"}, {"data-kind", "primary"}, {"data-x", "1"}],
                ["First"]},
               {"p", [], ["Outside div"]}
             ]

      assert capture_log(fn ->
               assert Xmerl.all(tree, "a:hover") == []
             end) =~ "Pseudo-class hover is not implemented. Ignoring."
    end

    test "with pseudo-element selector matches nothing", %{tree: tree} do
      assert Xmerl.all(tree, "p::before") == []
    end

    test "with descendant combinator selector", %{tree: tree} do
      assert Xmerl.all(tree, "body p") == [
               {"p", [{"class", "intro featured"}, {"data-kind", "primary"}, {"data-x", "1"}],
                ["First"]},
               {"p", [], ["Second"]},
               {"p", [], ["Outside div"]}
             ]
    end

    test "with child combinator selector", %{tree: tree} do
      assert Xmerl.all(tree, "body > p") == [{"p", [], ["Outside div"]}]
    end

    test "with adjacent sibling combinator selector", %{tree: tree} do
      assert Xmerl.all(tree, "p.intro + p") == [{"p", [], ["Second"]}]
    end

    test "with general sibling combinator selector", %{tree: tree} do
      assert Xmerl.all(tree, "p ~ [href]") == [
               {"a", [{"href", "/"}], ["Link"]},
               {"a", [{"href", "/go"}, {"class", "cta"}], ["Link"]}
             ]
    end

    test "with column combinator selector", %{tree: tree} do
      assert capture_log(fn ->
               assert Xmerl.all(tree, "p || a") == []
             end) =~ "Column combinator (||) is not implemented. Ignoring."
    end

    test "with multiple selector groups", %{tree: tree} do
      assert Xmerl.all(tree, "p.intro, a.cta") == [
               {"p", [{"class", "intro featured"}, {"data-kind", "primary"}, {"data-x", "1"}],
                ["First"]},
               {"a", [{"href", "/go"}, {"class", "cta"}], ["Link"]}
             ]
    end
  end

  describe "filter/2" do
    setup do
      html =
        """
        <div>
          <!--c-->
          <p>a</p>
          <h1>b</h1>
          <section class="x">
            <p>c</p>
          </section>
          <article>
            <h1>d</h1>
            <p>e</p>
          </article>
        </div>
        """

      {:ok, tree: Xmerl.parse(html)}
    end

    test "filters", %{tree: tree} do
      assert Xmerl.to_string(Xmerl.filter(tree, "h1, section.x")) ==
               """
               <div>
                 <!--c-->
                 <p>a</p>
                 <article>
                   <p>e</p>
                 </article>
               </div>
               """
    end

    test "with node input" do
      node = {"div", [], []}

      assert Xmerl.filter(node, "h1") == node
    end

    test "with list input" do
      nodes = [{"div", [], []}, {"p", [], []}]

      assert Xmerl.filter(nodes, "h1") == nodes
    end
  end

  describe "to_string/1" do
    test "with comment" do
      assert Xmerl.to_string({:comment, "note"}) == "<!--note-->"
    end

    test "with text" do
      assert Xmerl.to_string("a & b < c > d ©") == "a &amp; b &lt; c &gt; d ©"
    end

    test "with void element" do
      assert Xmerl.to_string({"br", [], []}) == "<br>"
      assert Xmerl.to_string({"img", [{"src", "/p"}], []}) == ~s(<img src="/p">)
    end

    test "with element" do
      assert Xmerl.to_string({"div", [], []}) == "<div></div>"

      assert Xmerl.to_string({"div", [], [{"p", [], ["x"]}, {"p", [], ["y"]}]}) ==
               "<div><p>x</p><p>y</p></div>"

      assert Xmerl.to_string({"p", [], ["text ", {:comment, "c"}, " more"]}) ==
               "<p>text <!--c--> more</p>"
    end

    test "with attributes" do
      assert Xmerl.to_string({"a", [{"href", "/"}, {"class", "x"}], []}) ==
               ~s(<a href="/" class="x"></a>)

      assert Xmerl.to_string({"a", [{"xlink:href", "/ns"}], []}) ==
               ~s(<a xlink:href="/ns"></a>)

      assert Xmerl.to_string({"a", [{"data-x", ~s(a & "b" <c>)}], []}) ==
               ~s(<a data-x="a &amp; &quot;b&quot; &lt;c&gt;"></a>)
    end

    test "with list input" do
      assert Xmerl.to_string([{"p", [], ["a"]}, "b"]) == "<p>a</p>b"
    end

    test "with parse round-trip" do
      tree = Xmerl.parse(~s(<div id="x"><p data-x="a &amp; b">Test</p></div>))

      assert Xmerl.to_string(tree) ==
               ~s(<div id="x"><p data-x="a &amp; b">Test</p></div>)
    end
  end

  describe "text/1" do
    test "produces text" do
      html = "<div>start <p>middle</p><!--c--> end</div>"

      assert Xmerl.text(Xmerl.parse(html)) == "start middle end"
    end
  end
end
