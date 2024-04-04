defmodule CSSEx.ExpandableApply.Test do
  use ExUnit.Case, async: true
  alias CSSEx.Parser

  test "expandable and apply 1" do
    assert {:ok, _,
            ".expandable{color:red;width:100px}.expandable.test{border:2px solid red}.exp_2{color:orange}.class-1{background-color:blue;color:red;height:50px;width:100px}.class-1.test{border:2px solid red}.class-2{color:green}.class-2 .class-inner{color:orange;width:200px}.class-2 .class-inner .expandable{color:red;width:100px}.class-2 .class-inner .expandable.test{border:2px solid red}\n"} =
             Parser.parse("""
             $!color red;
             @expandable .expandable {
               color: <$color$>;
               width: 100px;
               &.test {
                 border: 2px solid <$color$>;
               }
             }
             .class-1 {
               background-color: blue;
               @apply expandable;
               height: 50px;
             }
             @expandable .exp_2 {
               color: orange;
             }
             $!color purple;
             .class-2 {
               color: green;
               .class-inner {
                 color: magenta;
                 @apply !expandable exp_2;
                 width: 200px;
             }
             }
             """)
  end

  test "expandable and apply 2" do
    assert {:ok, _,
            ".expandable{color:red;width:100px}.expandable.test{border:2px solid red}.exp_2{color:orange;font-size:12px}.class-1{background-color:blue;color:red;height:50px;width:100px}.class-1.test{border:2px solid red}.class-2{color:green}.class-2 .class-inner{color:purple;font-size:12px;width:200px}.class-2 .class-inner.test{border:2px solid purple}\n"} =
             Parser.parse("""
             $!color red;
             @expandable .expandable {
               color: <$color$>;
               width: 100px;
               &.test {
                 border: 2px solid <$color$>;
               }
             }
             .class-1 {
               background-color: blue;
               @apply expandable;
               height: 50px;
             }
             @expandable .exp_2 {
               color: orange;
               font-size: 12px;
             }
             $!color purple;
             .class-2 {
               color: green;
               .class-inner {
                 color: magenta;
                 @apply exp_2 ?expandable;
                 width: 200px;
             }
             }
             """)
  end

  test "expandable and apply 3" do
    assert {:ok, _,
            ".hoverable{color:red}.hoverable:hover{color:rgba(204,0,0,1.0)}container .hoverable{background-color:black}.class-1{color:red}.class-1:hover{color:rgba(204,0,0,1.0)}container .class-1{background-color:black}.class-2 .hoverable{color:red}.class-2 .hoverable:hover{color:rgba(204,0,0,1.0)}.class-2 container .hoverable{background-color:black}.class-3{color:blue}.class-3:hover{color:rgba(0,0,204,1.0)}container .class-3{background-color:black}.class-4{color:red}.class-4:hover{color:rgba(204,0,0,1.0)}container .class-4{background-color:black}\n"} =
             Parser.parse("""
             $!color red;

             @expandable .hoverable {
               color: <$color$>;
               &:hover {
                 color: @fn::darken(<$color$>, 10);
               }
               container& {
                 background-color: black;
               }
             }
             .class-1 {
               @apply hoverable;
             }
             $!color blue;
             .class-2 {
               @apply !hoverable;
             }

             .class-3 {
               @apply ?hoverable;
             }

             .class-4 {
               @apply hoverable;
             }
             """)
  end

  test "expandable and eex blocks" do
    assert {:ok, _,
            ".class-2{color:white}@media screen and (max-width:768px){.test{color:red;font-size:12px}.class-1{color:red;font-size:12px}.class-3{color:blue;font-size:12px}.class-2 .test{color:red;font-size:12px}}@media screen and (min-width:1200px) and (max-width:1440px){.test{color:red;font-size:36px}.class-1{color:red;font-size:36px}.class-3{color:blue;font-size:36px}.class-2 .test{color:red;font-size:36px}}@media screen and (min-width:1440px) and (max-width){.test{color:red;font-size:40px}.class-1{color:red;font-size:40px}.class-3{color:blue;font-size:40px}.class-2 .test{color:red;font-size:40px}}@media screen and (min-width:768px) and (max-width:992px){.test{color:red;font-size:18px}.class-1{color:red;font-size:18px}.class-3{color:blue;font-size:18px}.class-2 .test{color:red;font-size:18px}}@media screen and (min-width:992px) and (max-width:1200px){.test{color:red;font-size:24px}.class-1{color:red;font-size:24px}.class-3{color:blue;font-size:24px}.class-2 .test{color:red;font-size:24px}}\n"} =
             Parser.parse("""
             $!color red;
             @!screen_breakpoints [
             sm: "0px",
             md: "768px",
             lg: "992px",
             xl: "1200px",
             xxl: "1440px",
             ];

             @!sizes %{
             sm: 12,
             md: 18,
             lg: 24,
             xl: 36,
             xxl: 40
             };

             @fn breakpoint_min_max(min_bp, max_bp, breakpoints) ->
             min_bp = String.to_existing_atom(min_bp)
             max_bp = String.to_existing_atom(max_bp)
             keys = Keyword.keys(breakpoints)
             min_index = Enum.find_index(keys, fn(x) -> x == min_bp end)
             min = Keyword.get(breakpoints, min_bp)

             max = case max_bp && max_bp != min_bp do
             true -> Keyword.get(breakpoints, max_bp)
             false -> Keyword.get(breakpoints, Enum.at(keys, min_index + 1))
             end

             %CSSEx.Unit{value: val} = CSSEx.Unit.new_unit(min)
             min_text = if(val > 0, do: " and (min-width: \#{min})", else: "")

             "@media screen\#{min_text} and (max-width: \#{max}) { \#{ctx_content} }"  
             end;

             @expandable .test {
             <%=  for {k, _width} <- @screen_breakpoints, reduce: "" do
               acc ->
                 acc <> "@fn::breakpoint_min_max(\#{k}, false, @::screen_breakpoints,
                    font-size: \#{Map.get(@sizes, k)}px;
             color: <$color$>
                 )"
             end %>
             }

             .class-1 {
               @apply test;
             }
             $!color blue;

             .class-3 {
               @apply ?test;
             }

             .class-2 {
               @apply !test;
               color: white;
             }
             """)
  end
end
