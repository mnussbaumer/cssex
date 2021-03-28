defmodule CSSEx.Import.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  @basic """
  @!width 567px;
  @charset "UTF-8";
  @import "test.css";
  @import url("/other.css") print;
  @import url("/other.css") screen and (max-width: <$width$>);
  .test{color:red;}
  """

  test "basic import statements" do
    assert {:ok, _,
            "@charset \"UTF-8\";@import \"test.css\";@import url(\"/other.css\") print;@import url(\"/other.css\") screen and (max-width: 567px);.test{color:red}\n"} =
             Parser.parse(@basic)
  end
end
