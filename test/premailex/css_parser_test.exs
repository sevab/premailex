defmodule Premailex.CSSParserTest do
  use ExUnit.Case
  doctest Premailex.CSSParser

  alias Premailex.CSSParser

  import ExUnit.CaptureLog

  @input """
  @charset "UTF-8";
  @import url("a;b'.css");
  @import "with\\"-escaped-quote.css";
  body, table {/* text-decoration:underline */background-color:#ffffff;background-image:url('http://example.com/image.png');color:#000000;}
  div p > a:hover {color:#000000 !important;text-decoration:underline}
  /*div {
    padding:10px
  }*/
  @media screen and (max-width: 600px) {
    body {
      width: auto;
    }
  }
  @font-face {
    font-family: "Open Sans";
    src: url("/fonts/OpenSans-Regular-webfont.woff2") format("woff2"),
         url("/fonts/OpenSans-Regular-webfont.woff") format("woff");
  }
  .with\\,escaped\\,commas {}
  .with-empty-selector, {}
  """

  @parsed [
    %{
      declarations: [
        %{property: "background-color", value: "#ffffff", important?: false},
        %{
          property: "background-image",
          value: "url('http://example.com/image.png')",
          important?: false
        },
        %{property: "color", value: "#000000", important?: false}
      ],
      selector: "body",
      specificity: {0, 0, 0, 1}
    },
    %{
      declarations: [
        %{property: "background-color", value: "#ffffff", important?: false},
        %{
          property: "background-image",
          value: "url('http://example.com/image.png')",
          important?: false
        },
        %{property: "color", value: "#000000", important?: false}
      ],
      selector: "table",
      specificity: {0, 0, 0, 1}
    },
    %{
      declarations: [
        %{property: "color", value: "#000000 !important", important?: true},
        %{property: "text-decoration", value: "underline", important?: false}
      ],
      selector: "div p > a:hover",
      specificity: {0, 0, 1, 3}
    },
    %{
      declarations: [],
      selector: ".with\\,escaped\\,commas",
      specificity: {0, 0, 1, 0}
    },
    %{
      declarations: [],
      selector: ".with-empty-selector",
      specificity: {0, 0, 1, 0}
    }
  ]

  describe "parse/1" do
    test "with empty input" do
      assert CSSParser.parse("") == []
      assert CSSParser.parse("   \n\t  \r\n") == []
    end

    test "with unterminated comment" do
      assert CSSParser.parse("""
             h1 {
               color: blue;
             }
             div {
               color: red; /* unclosed comment
               padding: 10px;
             }
             """) ==
               [
                 %{
                   declarations: [%{property: "color", value: "blue", important?: false}],
                   selector: "h1",
                   specificity: {0, 0, 0, 1}
                 }
               ]
    end

    test "with unterminated at-rule string" do
      assert CSSParser.parse("""
             h1 { color: blue; }
             @import "unclosed string;
             div { color: red; }
             """) == [
               %{
                 declarations: [%{value: "blue", property: "color", important?: false}],
                 selector: "h1",
                 specificity: {0, 0, 0, 1}
               }
             ]
    end

    test "with unterminated at-rule block" do
      assert CSSParser.parse("""
             h1 { color: blue; }
             @media (max-width: 600px) {
               body {
                 color: red;
             }
             div { color: red; }
             """) == [
               %{
                 declarations: [%{value: "blue", property: "color", important?: false}],
                 selector: "h1",
                 specificity: {0, 0, 0, 1}
               }
             ]
    end

    test "with unterminated rule block" do
      assert CSSParser.parse("""
             h1 { color: blue; }
             div { color: red;
             span { color: green; }
             """) ==
               [
                 %{
                   declarations: [%{property: "color", value: "blue", important?: false}],
                   selector: "h1",
                   specificity: {0, 0, 0, 1}
                 }
               ]
    end

    test "with rule block with missing selector" do
      assert CSSParser.parse("""
             { color: red; }
             h1 { color: blue; }
             """) ==
               [
                 %{
                   declarations: [%{property: "color", value: "blue", important?: false}],
                   selector: "h1",
                   specificity: {0, 0, 0, 1}
                 }
               ]
    end

    test "with rule with missing value" do
      assert CSSParser.parse("""
             h1 { color: ; }
             div { color: }
             """) ==
               [
                 %{declarations: [], selector: "h1", specificity: {0, 0, 0, 1}},
                 %{declarations: [], selector: "div", specificity: {0, 0, 0, 1}}
               ]
    end

    test "parses" do
      assert CSSParser.parse(@input) == @parsed
    end

    test "with varying specificity" do
      assert [
               %{
                 selector: "div#id.cls1.cls2[a][b]:hover > p",
                 specificity: {0, 1, 5, 2} = specificity_1
               },
               %{
                 selector: "*::before",
                 specificity: {0, 0, 0, 1} = specificity_2
               }
             ] =
               CSSParser.parse("""
               div#id.cls1.cls2[a][b]:hover > p { color: red; }
               *::before { content: ''; }
               """)

      assert specificity_1 > specificity_2
    end
  end

  describe "split_selector_groups/1" do
    test "with empty selector" do
      assert CSSParser.split_selector_groups("") == []
    end

    test "with whitespace selector" do
      assert CSSParser.split_selector_groups("\t") == []
      assert CSSParser.split_selector_groups("    ") == []
    end

    test "with commas selector" do
      assert CSSParser.split_selector_groups(",,,,") == []
    end

    test "with comma separated selectors" do
      assert CSSParser.split_selector_groups("div  ,  .foo,\t.bar") == [
               "div",
               ".foo",
               ".bar"
             ]
    end

    test "with comma separated selectors with newlines" do
      assert CSSParser.split_selector_groups("""
               div ,
             .foo,
             .bar
             """) == ["div", ".foo", ".bar"]
    end

    test "with comma separated selectors with consecutive commas" do
      assert CSSParser.split_selector_groups(",.foo,,,.bar,,") == [".foo", ".bar"]
    end

    test "with comma separated selectors with escaped commas" do
      assert CSSParser.split_selector_groups(".with\\,escaped\\,commas") == [
               ~s(.with\\,escaped\\,commas)
             ]
    end

    test "with attribute selector" do
      assert CSSParser.split_selector_groups("span[data-y], .foo") ==
               ["span[data-y]", ".foo"]
    end

    test "with attribute selector with brackets" do
      assert CSSParser.split_selector_groups("[[data]], .foo") == [
               "[[data]]",
               ".foo"
             ]
    end

    test "with attribute selector with newlines" do
      assert CSSParser.split_selector_groups("[data\nattr], .foo") == [
               "[data\nattr]",
               ".foo"
             ]
    end

    test "with malformed attribute selector" do
      assert CSSParser.split_selector_groups("[data, .foo") == ["[data, .foo"]

      assert CSSParser.split_selector_groups("data], .foo") == [
               "data]",
               ".foo"
             ]
    end

    test "with attribute selector with quoted value" do
      assert CSSParser.split_selector_groups(~s([data='a,b,c'] + [data="x,y"], .bar)) ==
               [~s([data='a,b,c'] + [data="x,y"]), ".bar"]
    end

    test "with attribute selector with quoted value containing quote" do
      assert CSSParser.split_selector_groups(~s([data='a,"b,c'] + [data="x,'y"], .bar)) ==
               [~s([data='a,"b,c'] + [data="x,'y"]), ".bar"]
    end

    test "with attribute selector with quoted value with escaped quotes" do
      assert CSSParser.split_selector_groups(~s([data='a,\\'b,c'] + [data="x,\\"y"], .bar)) == [
               ~s([data='a,\\'b,c'] + [data="x,\\"y"]),
               ".bar"
             ]
    end

    test "with attribute selector with quoted value containing brackets" do
      assert CSSParser.split_selector_groups(~s([href="a]b"], [data-x="a[b"])) ==
               [~s([href="a]b"]), ~s([data-x="a[b"])]
    end

    test "with attribute selector with quoted value with newlines" do
      assert CSSParser.split_selector_groups("[data=\"line1\nline2\"], .foo") == [
               "[data=\"line1\nline2\"]",
               ".foo"
             ]
    end

    test "with attribute selector with malformed quoted value" do
      assert CSSParser.split_selector_groups(~s([data="a,b,c], .foo)) == [
               ~s([data="a,b,c], .foo)
             ]

      assert CSSParser.split_selector_groups(~s([data=a,b,c"], .foo)) == [
               ~s([data=a,b,c"], .foo)
             ]
    end

    test "with functional pseudo class selector" do
      assert CSSParser.split_selector_groups("div:not(.foo, .bar), .baz") == [
               "div:not(.foo, .bar)",
               ".baz"
             ]
    end

    test "with nested functional pseudo class selector" do
      assert CSSParser.split_selector_groups("div:is(:not(.foo, .bar), .baz), .qux") ==
               [
                 "div:is(:not(.foo, .bar), .baz)",
                 ".qux"
               ]
    end

    test "with functional pseudo class selector with newlines" do
      assert CSSParser.split_selector_groups("div:not(\n.foo, .bar\n), .baz") == [
               "div:not(\n.foo, .bar\n)",
               ".baz"
             ]
    end

    test "with malformed functional pseudo class selector" do
      assert CSSParser.split_selector_groups("div:not(.foo, .bar, .baz") == [
               "div:not(.foo, .bar, .baz"
             ]

      assert CSSParser.split_selector_groups("div:not.foo, .bar), .baz)") == [
               "div:not.foo",
               ".bar)",
               ".baz)"
             ]
    end
  end

  describe "parse_selector_groups/1" do
    test "with tag selector" do
      assert [[%{tag: "p"}]] = CSSParser.parse_selector_groups("p")
      assert [[%{tag: "*"}]] = CSSParser.parse_selector_groups("*")
    end

    test "with id selector" do
      assert [[%{id: "main"}]] = CSSParser.parse_selector_groups("#main")
    end

    test "with invalid id selector" do
      assert_invalid_selector("body#")
      assert_invalid_selector("##main")
      assert_invalid_selector("#.container")
      assert_invalid_selector("#:first-of-type")
      assert_invalid_selector("#[href]")
      assert_invalid_selector("# div")
    end

    test "with class selector" do
      assert [[%{classes: ["a"]}]] = CSSParser.parse_selector_groups(".a")
      assert [[%{classes: ["a", "b"]}]] = CSSParser.parse_selector_groups(".a.b")
    end

    test "with invalid class selector" do
      assert_invalid_selector("p.")
      assert_invalid_selector("..x")
      assert_invalid_selector(".#x")
      assert_invalid_selector(".:x")
      assert_invalid_selector(".[a]")
      assert_invalid_selector(". x")
      assert_invalid_selector(".(x)")
    end

    test "with attribute selector" do
      assert [[%{attrs: ["href"]}]] = CSSParser.parse_selector_groups("[href]")
      assert [[%{attrs: ["href"]}]] = CSSParser.parse_selector_groups("[ href\n\t]")

      assert [[%{attrs: [{"href", "/go"}]}]] = CSSParser.parse_selector_groups(~s([href="/go"]))
      assert [[%{attrs: [{"href", "/go"}]}]] = CSSParser.parse_selector_groups(~s([href='/go']))
      assert [[%{attrs: [{"href", "/go"}]}]] = CSSParser.parse_selector_groups("[href=/go]")

      assert [[%{attrs: [{"href", "/go"}]}]] =
               CSSParser.parse_selector_groups(~s([\nhref="/go"\t ]))

      assert [[%{attrs: ["href", {"class", "cta"}]}]] =
               CSSParser.parse_selector_groups("[href][class=cta]")
    end

    test "with attribute selector with value containing special chars" do
      assert [[%{attrs: [{"x", "a b"}]}]] =
               CSSParser.parse_selector_groups(~s([x="a b"]))

      assert [[%{attrs: [{"x", "a,b"}]}]] =
               CSSParser.parse_selector_groups(~s([x='a,b']))

      assert [[%{attrs: [{"x", "a'b"}]}]] =
               CSSParser.parse_selector_groups(~s([x="a'b"]))

      assert [[%{attrs: [{"x", "a\"b"}]}]] =
               CSSParser.parse_selector_groups(~S([x="a\"b"]))

      assert [[%{attrs: [{"x", "a[b"}]}]] =
               CSSParser.parse_selector_groups(~s([x="a[b"]))

      assert [[%{attrs: [{"x", "a]b"}]}]] =
               CSSParser.parse_selector_groups(~s([x="a]b"]))

      assert [[%{attrs: [{"x", "a(b"}]}]] =
               CSSParser.parse_selector_groups(~s|[x="a(b"]|)

      assert [[%{attrs: [{"x", "a)b"}]}]] =
               CSSParser.parse_selector_groups(~s|[x="a)b"]|)
    end

    test "with invalid attribute selector" do
      assert_invalid_selector("a[")
      assert_invalid_selector("a]")
      assert_invalid_selector("a[]")
      assert_invalid_selector("a[[href]")
      assert_invalid_selector("a[[href]]")
      assert_invalid_selector("a[href href]")
      assert_invalid_selector(~s(a[href=/"go]))
      assert_invalid_selector(~s(a[href="/go]))
      assert_invalid_selector(~s(a[href="/g"o]))
      assert_invalid_selector(~s|a[href=/g(o]|)
      assert_invalid_selector(~s|a[href=/go)]|)
    end

    test "with pseudo class selector" do
      assert [[%{pseudos: [%{name: "first-of-type", expression: nil, kind: :pseudo_class}]}]] =
               CSSParser.parse_selector_groups(":first-of-type")

      assert [[%{pseudos: [%{name: "nth-child", expression: "2", kind: :pseudo_class}]}]] =
               CSSParser.parse_selector_groups(":nth-child(2)")

      assert [[%{pseudos: [%{name: "required"}, %{name: "invalid"}]}]] =
               CSSParser.parse_selector_groups(":required:invalid")

      assert [[%{pseudos: [%{name: "not", expression: ":has(.foo)"}]}]] =
               CSSParser.parse_selector_groups(":not(:has(.foo))")

      assert [[%{pseudos: [%{name: "not", expression: ".a > .b"}]}]] =
               CSSParser.parse_selector_groups(":not(.a > .b)")
    end

    test "with invalid pseudo class selector" do
      assert_invalid_selector("a:")
      assert_invalid_selector(":#x")
      assert_invalid_selector(":.x")
      assert_invalid_selector(":[a]")
      assert_invalid_selector(": x")
      assert_invalid_selector("a:()")
      assert_invalid_selector("p:nth-child(")
      assert_invalid_selector("p:nth-child(2))")
    end

    test "with pseudo element selector" do
      assert [[%{pseudos: [%{name: "before", kind: :pseudo_element}]}]] =
               CSSParser.parse_selector_groups("::before")

      assert [[%{pseudos: [%{name: "part", expression: "title", kind: :pseudo_element}]}]] =
               CSSParser.parse_selector_groups("::part(title)")
    end

    test "with invalid pseudo element selector" do
      assert_invalid_selector("a::")
      assert_invalid_selector("a::()")
    end

    test "with descendant combinator selector" do
      assert [[%{tag: "p", combinator: nil}, %{tag: "body", combinator: :descendant}]] =
               CSSParser.parse_selector_groups("body p")

      assert [[%{tag: "p", combinator: nil}, %{tag: "body", combinator: :descendant}]] =
               CSSParser.parse_selector_groups("  body   p  ")

      assert [[%{tag: "p", combinator: nil}, %{tag: "body", combinator: :descendant}]] =
               CSSParser.parse_selector_groups("body\np")
    end

    test "with child combinator selector" do
      assert [[%{tag: "p", combinator: nil}, %{tag: "body", combinator: :child}]] =
               CSSParser.parse_selector_groups("body>p")

      assert [[%{tag: "p", combinator: nil}, %{tag: "body", combinator: :child}]] =
               CSSParser.parse_selector_groups("body\n>\np")
    end

    test "with adjacent sibling combinator selector" do
      assert [[%{tag: "p", combinator: nil}, %{tag: "div", combinator: :adjacent}]] =
               CSSParser.parse_selector_groups("div + p")
    end

    test "with general sibling combinator selector" do
      assert [[%{tag: "p", combinator: nil}, %{tag: "div", combinator: :sibling}]] =
               CSSParser.parse_selector_groups("div ~ p")
    end

    test "with column combinator selector" do
      assert [[%{tag: "p", combinator: nil}, %{tag: "div", combinator: :column}]] =
               CSSParser.parse_selector_groups("div || p")
    end

    test "with invalid combinator selector" do
      assert_invalid_selector("> p")
      assert_invalid_selector("+ p")
      assert_invalid_selector("~ p")
      assert_invalid_selector("|| p")
      assert_invalid_selector("div >")
      assert_invalid_selector("div +")
      assert_invalid_selector("div ~")
      assert_invalid_selector("div ||")
      assert_invalid_selector("div > > p")
    end

    test "with multiple selector groups" do
      assert [[%{tag: "p", classes: ["intro"]}], [%{tag: "a", classes: ["cta"]}]] =
               CSSParser.parse_selector_groups("p.intro, a.cta")
    end
  end

  defp assert_invalid_selector(selector) do
    assert capture_log(fn ->
             assert CSSParser.parse_selector_groups(selector) == [[]]
           end) =~ ~s(Invalid selector group "#{selector}". Ignoring.)
  end

  describe "parse_declaration_block/1" do
    test "with empty declaration block" do
      assert CSSParser.parse_declaration_block("") == []
      assert CSSParser.parse_declaration_block("   \n\t  \r\n") == []
    end

    test "with semicolon declaration block" do
      assert CSSParser.parse_declaration_block(";;;;") == []
    end

    test "with declaration missing property" do
      assert CSSParser.parse_declaration_block("color red") == []
      assert CSSParser.parse_declaration_block(": red") == []
    end

    test "with declaration missing value" do
      assert CSSParser.parse_declaration_block("color") == []
      assert CSSParser.parse_declaration_block("color: ") == []
    end

    test "with declaration" do
      assert CSSParser.parse_declaration_block("color: red;background-color: blue;") ==
               [
                 %{property: "color", value: "red", important?: false},
                 %{property: "background-color", value: "blue", important?: false}
               ]
    end

    test "with declaration without trailing semicolon" do
      assert CSSParser.parse_declaration_block("color: red") ==
               [
                 %{property: "color", value: "red", important?: false}
               ]
    end

    test "with declarations with newline" do
      assert CSSParser.parse_declaration_block("""
             color: red;
             background:
             blue;
             """) ==
               [
                 %{property: "color", value: "red", important?: false},
                 %{property: "background", value: "blue", important?: false}
               ]
    end

    test "with declarations with whitespace" do
      assert CSSParser.parse_declaration_block("""
             color  :  red  ;
             background:\tblue\t;
             """) ==
               [
                 %{property: "color", value: "red", important?: false},
                 %{property: "background", value: "blue", important?: false}
               ]
    end

    test "with declaration with !important value" do
      assert CSSParser.parse_declaration_block("""
             color: red !important ;
             background-color: blue !IMPORTANT;
             text-decoration: underline !important;
             width: 100px!important
             """) ==
               [
                 %{property: "color", value: "red !important", important?: true},
                 %{property: "background-color", value: "blue !IMPORTANT", important?: true},
                 %{property: "text-decoration", value: "underline !important", important?: true},
                 %{property: "width", value: "100px!important", important?: true}
               ]
    end

    test "with declaration with malformed !important" do
      assert CSSParser.parse_declaration_block(
               "color: !important red;background: blue !important\""
             ) ==
               [
                 %{property: "color", value: "!important red", important?: false},
                 %{property: "background", value: "blue !important\"", important?: false}
               ]
    end

    test "with malformed declaration" do
      assert CSSParser.parse_declaration_block("color red background: blue") ==
               [
                 %{property: "color red background", value: "blue", important?: false}
               ]
    end

    test "with declaration value containing semicolon" do
      assert CSSParser.parse_declaration_block("""
             content: "a;b";
             background: url(data:image/png;base64,abc);
             color: red;
             """) == [
               %{property: "content", value: "\"a;b\"", important?: false},
               %{
                 property: "background",
                 value: "url(data:image/png;base64,abc)",
                 important?: false
               },
               %{property: "color", value: "red", important?: false}
             ]
    end
  end

  test "merge/1" do
    rules =
      CSSParser.parse("""
      p { color: red !important; font-size: 12px; }
      p { color: blue; font-size: 14px; }
      """)

    assert CSSParser.merge(rules) == [
             %{property: "color", value: "red !important", important?: true},
             %{property: "font-size", value: "14px", important?: false}
           ]
  end

  test "to_string/1" do
    [%{declarations: [declaration_1, declaration_2]}] =
      CSSParser.parse("""
      p { color: red !important; font-size: 12px; }
      """)

    assert CSSParser.to_string(declaration_1) == "color: red !important;"

    assert CSSParser.to_string([declaration_1, declaration_2]) ==
             "color: red !important; font-size: 12px;"
  end
end
