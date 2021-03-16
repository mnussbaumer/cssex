defmodule Mix.Tasks.CSS.Parser do
  @moduledoc """
  The entry point to the parser task. It takes a filename path and it tries to parse it into CSS, no additional options available as of now.

  The target file can use any of elixir's templating capabilities to produce the intermediate version before CSS expansion. It has access only to scoped variables declared in the cssex tree, available as assigns. 

  This means two things happen, if a cssex file imports other cssex files the imported cssex files while being processed will be able to use variables declared previously in the current scope and any variable declaration in them will shadow any previously declared ones until the current scope ends.

  There's 6 kinds of variables that can be declared:

    @!variable value;
   
  This is a normal variable that can shadow any other previously declared until the root original scope runs to its end.


    @()variable value;

  This is a normal variable that will only be set in the current scope of cssex file being parsed. Once the file ends it's value is returned to what it was on the outside scope.


    @?variable value;

  This is a conditional variable that will only be set if a same named variable isn't available in the current scope. It's limited to the current cssex file being parsed.

  These previous three declarations' values are as is, string representations to be injected in the final CSS, you shouldn't use quotes around the values, e.g.:

    @!test 16px;
    
  Will create a @!test variable usable throughout the following cssex file and imported files inside it through the syntax @$$test, including inside <%= eex blocks %> declared in any of the outer or child templates.


  Placing a * after the @ character creates as well a normal css variable, this css variable due to CSS scoping has different nuances, but basically will, if declared at the top level of a parsing step (not inside any CSS identifier), create a variable in the :root element, otherwise, it will create a variable inside whatever CSS definition it's in, e.g.:

  @*!color red;

  .sample-div {
     @*!color blue;
     color: @$$color;
  }

  p { color: @$$color; }

  Will generate:

    :root {
       --color: red;
    }

    .sample-div {
       --color: blue;
       color: blue;
    }

    p { color: blue; }

  But on the other hand:

    @*!color red;

    .sample-div {
       @*()color blue;
       color: @$$color;
    }

    p { color: @$$color; }

  Will generate:

    :root {
       --color: red;
    }

    .sample-div {
       --color: blue;
       color: blue;
    }

    p { color: red; }

  Lastly

    %!variable %{
      elixir_map: binary_string
    };
    %()variable same;
    %?variable same;

  This is exactly the same as before but these variables are only available inside eex templates and can hold any elixir term, where each key has a value that is either another map or a binary_string. The values when strings needs to be delimited by quotes as normal elixir strings. To use them in an eex block you would do:

    %::variable_name

  The termination of an assign has to always be ; followed by a newline indicator.

  An example would be:

    %!map_colors %{color_1: "red", color_2: "blue"};

    button {
      <%= for {color_key, color} <- %::map_colors do %>
        \"""
  &.\#{color_key} {
    color: \#{color};
    &:hover {
      color: lighten(\#{color}, 10%);
    }
  }
  \"""
      <%= end %>
    }


  Which would result in an intermediate expression of:

    button {
       &.color_1 { 
         color: red;
  &:hover {
    color: lighten(red, 10%);
  }
       }
       &.color_2 { 
         color: blue;
  &:hover {
    color: lighten(blue, 10%);
  }
       }
    }

  When the eex compilation was done, and finally end up as:

    button.color_1 { color: red;}
    button.color_1:hover { color: #sfjsjh; }
    button.color_2 { color: blue;}
    button.color_2:hover { color: #tkgigd; }

  When the final cssex parsing was done.

  Using @$$variable name inside a eex template does nothing, those variables will be replaced only after the eex evaluation. You can run any code inside an eex block, but it must return a String.t, or list of binaries, as those will be written as String.t(s) into the file before the final cssex expansion.
  """
end
