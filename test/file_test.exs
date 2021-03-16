defmodule CSSEx.File.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  setup do
    {:ok, cwd} = File.cwd()
    root = Path.join([cwd, "test", "files"])
    final_base = Path.join([root, "finals"])

    assert {:ok, _} = File.rm_rf(final_base)
    refute File.exists?(final_base)

    target_originals = Path.join([root, "originals"])
    target_originals_relative = Path.join([root, "originals_relative"])

    assert {:ok, _} = File.rm_rf(target_originals)
    assert {:ok, _} = File.rm_rf(target_originals_relative)

    refute File.exists?(target_originals)
    refute File.exists?(target_originals_relative)

    assert :ok = File.mkdir(target_originals)
    assert :ok = File.mkdir(target_originals_relative)
    assert {:ok, _} = File.cp_r(Path.join([root, "originals_templates"]), target_originals)

    assert {:ok, _} =
             File.cp_r(
               Path.join([root, "originals_relative_templates"]),
               target_originals_relative
             )

    {:ok, %{target_originals: target_originals}}
  end

  @full_final_css ".test_2{background-color:#ffffff;color:#000000;}.test_1{background-color:#000000;color:#ffffff;}div{color:black;color:white;background-color:red;}div:hover{cursor:pointer;background-color:green;color:purple;}\n"

  test "parses a file", %{target_originals: base_path} do
    final_path = Path.join([base_path, "test_1.cssex"])

    assert {
             :ok,
             _,
             @full_final_css
           } = Parser.parse_file(base_path, final_path)
  end

  test "entry points", %{target_originals: target_originals} do
    base_path = Path.join(["test", "files", "originals", "test_1.cssex"])
    final_path = Path.join(["test", "files", "finals", "test_1.css"])
    entry_points = Map.put(%{}, base_path, final_path)
    {:ok, pid} = CSSEx.start_link(%CSSEx{entry_points: entry_points})

    assert :ready = :gen_statem.call(pid, :status)
    assert File.exists?(final_path)

    assert {:ok, @full_final_css} = File.read(final_path)

    to_change_original = Path.join([target_originals, "test_1.cssex"])
    {:ok, original_handler} = File.open(to_change_original, [:append])

    to_write = ".write{color:red;}"
    IO.write(original_handler, to_write)
    assert :ok = File.close(original_handler)

    # because the file system notification events can be flaky on setup and due to timing, we stream 1 repeatedly up to 10 seconds. At every 1 second we open and close the file to get the events to bubble up. Every other 200ms interval we check to see if the final file when split has the desired state and if not, we sleep for another 200ms.
    assert Enum.reduce_while(Stream.cycle([1]), 0, fn _, acc ->
             case Integer.mod(acc, 5) do
               _ when acc == 50 ->
                 {:halt, false}

               0 ->
                 {:ok, original_handler} = File.open(to_change_original, [:append])
                 assert :ok = File.close(original_handler)
                 {:cont, acc + 1}

               _ ->
                 assert :ready = :gen_statem.call(pid, :status)
                 assert {:ok, final_css} = File.read(final_path)

                 # the splitted final_css should have 5 parts + one "\n" , and one of those parts when added the } (used to split) will be equal to the to_write value
                 case String.split(final_css, "}") do
                   [_, _, _, _, _, "\n"] = splits ->
                     assert Enum.any?(splits, fn split ->
                              split <> "}" =~ to_write
                            end)

                     {:halt, true}

                   _ ->
                     Process.sleep(200)
                     {:cont, acc + 1}
                 end
             end
           end)
  end
end
