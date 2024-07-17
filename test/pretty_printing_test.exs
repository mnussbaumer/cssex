defmodule CSSEx.PrettyPrinting.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @source """
  @!var %{
    test_1: %{
      "color" => "#ffffff",
      "background-color" => "#000000"
    },
    test_2: %{
      "color" => "#000000",
      "background-color" => "#ffffff"
    }
  };

  <%= for {key, val} <- @var, reduce: "" do
    acc ->
      IO.iodata_to_binary(
        [acc, ".", \"\#{key}\", "{",
      	(for {attr, value} <- val, reduce: [] do
      	  acc_2 -> [acc_2, attr, ":", value, ";"]
        end), 
      "}"])
    end %>

  div { color: black; }

  @media (max-width: 600px) and (min-width: 400px) {
    div {color: red;}
    }
  """

  @output """
  .test_1 {
      background-color: #000000;
      color: #ffffff
  }

  .test_2 {
      background-color: #ffffff;
      color: #000000
  }

  div {
      color: black
  }

  @media (max-width:600px) and (min-width:400px) {
      div {
          color: red
      }


  }


  """

  setup do
    {:ok, cwd} = File.cwd()
    final_base = Path.join([cwd, "test", "files", "pretty_printing"])

    assert {:ok, _} = File.rm_rf(final_base)
    refute File.exists?(final_base)

    assert :ok = File.mkdir(final_base)
    assert File.exists?(final_base)

    final_file = Path.join([final_base, "final.css"])

    on_exit(fn -> File.rm_rf!(final_base) end)

    {:ok, %{base_path: final_base, final_file: final_file}}
  end

  test "parsing content with pretty print without file" do
    assert output =
             Parser.parse(@source, pretty_print?: true)

    assert {:ok, _, @output} =
             Parser.parse(@source, pretty_print?: true)
  end

  test "parsing content with pretty print to file", %{final_file: final_file} do
    assert {:ok, _, []} = Parser.parse(nil, @source, final_file, pretty_print?: true)
    assert @output = File.read!(final_file)
  end
end
