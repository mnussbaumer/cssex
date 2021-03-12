defmodule CSSEx.Parser.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @test_cases [
    {
      "basic variable replacement",
      """
      @!test 16px;
      
      div { width: @$$test; }
      """,
      """
      div{width:16px;}
      """
    },

    {
      "variable replacement and root placing of css var",
      """
      @*!test 16px;

      div {
         width: @$$test;
      }
      """,
      [
	"div{width:16px;}",
	":root{--test:16px;}"
      ]
    },

    {
      "assigns work correctly",
      """
      %!test %{
        test_1: :b,
        test_2: 1
      };

      """,
      "\n"
    },

    {
      "assigns can be used in eex blocks",
      """
      %!var %{
        test_1: %{
      	  "color" => "#ffffff",
      	  "background-color" => "#000000"
      	},
      	test_2: %{
      	  "color" => "#000000",
      	  "background-color" => "#ffffff"
        }
      };
      
      <%= for {key, val} <- %::var, reduce: "" do
        acc ->
          IO.iodata_to_binary(
      	    [acc, ".", \"\#{key}\", "{",
      	    (for {attr, value} <- val, reduce: [] do
      	      acc_2 -> [acc_2, attr, ":", value, ";"]
            end), 
      	  "}"])
      end %>
      test }
      div { color: black; }
      """,
      [
	".test_1{background-color:#000000;color:#ffffff;}",
	".test_2{background-color:#ffffff;color:#000000;}",
	"div{color:black;}",
	[false, "test }"]
      ]
    },

    {
      "interpolation works in attributes",
      """
      @!test px;
      
      div {
        border: 2<$test$> solid red;
      }
      """,
      "div{border:2px solid red;}\n"
    },

    {
      "interpolation works in rules and other non-attributes",
      """
      @!test sm;
      div.<$test$>{border:2px solid red;
      }
      """,
      "div.sm{border:2px solid red;}\n"
    }
  ]


  Enum.each(@test_cases, fn({subtitle, original, final_target}) ->
    case final_target do
      [_|_] ->
	test "parsing assertions ::: #{subtitle}" do
	  assert {:ok, _, parsed} = Parser.parse(unquote(original))
	  Enum.each(unquote(final_target), fn
	    ([false, match]) -> refute parsed =~ match
	    (match) -> assert parsed =~ match
	  end)
	end
      _ ->
	test "parsing assertions #{subtitle}" do
	  assert {:ok, _, unquote(final_target)} = Parser.parse(unquote(original))
	end
    end
  end)
end
