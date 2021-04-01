# CSSEx

A small pre-processing extension language for CSS written in Elixir.
Its main purpose is to provide a native Elixir pre-processor for CSS, in the vein of Sass/Scss.

<div align="center">
     <a href="#syntax">syntax</a><span>&nbsp; |</span>
     <a href="#caveats">Caveats</a><span>&nbsp; |</span>
     <a href="#installation">Installation</a><span>&nbsp; |</span>
     <a href="#usage">Usage</a><span>&nbsp; |</span>
     <a href="#tasks">Tasks</a><span>&nbsp; |</span>
     <a href="#internals">Internals</a><span>&nbsp; |</span>
     <a href="#roadmap">Roadmap</a><span>&nbsp; |</span>
     <a href="#about">About</a><span>&nbsp; |</span>
     <a href="#copyright">Copyright</a>
</div>


<div id="syntax"></div>

### Syntax:

<ul>
  <li><a href="#selectors">Selectors</a></li>
  <li><a href="#variables">Variables</a></li>
  <li><a href="#assigns">Assigns</a></li>
  <li><a href="#functions">Functions</a></li>
  <li><a href="#eex">EEx Blocks</a></li>
  <li><a href="#comments">Comments</a></li>
  <li><a href="#reserved">Reserved Tokens</a></li>
</ul>

<div id="selectors"></div>

#### Nested selectors and '&' concatenation

```css
button {
    background-color: blue;
    color: white;
    padding: 5px;
    
    .class_1 {
      color: yellow;
        svg&, .child {
 	  fill: red;
	}
    }

    &.concatenated_class {
      padding: 10px;
    }

    @media screen and (max-width: 756px) {
    	   font-size: 24px;
	   @media and (min-width: 500px) {
	   	  font-weight: 300;
           }
    }
}
```

##### into

```css
button { background-color: blue; color: white; padding: 5px }
button .class_1  { color: yellow }
button svg.class_1, button .class_1.child { fill: red }
button.concatenated_class { padding: 10px }

@media screen and (max-width: 756px) { button { font-size: 24px } }
@media screen and (max-width: 756px) and (min-width: 500px) { button { font-weight: 300 } }
```

The `&` operator can only be used inside a block and either at the start or end of each selector (or if single inside a `:not(&)`, or `:is(&)`).
If it's at the start it will append that selector to the parent, unless it's a tag selector (`p`, `canvas`, `your-custom-element`, etc) in which case it will prepend itself, and raise an error if you're trying to do so with a parent tag.

If it's at the end then the selector becomes the parent of it's parent.

```css
div, section {
  &.concat, .parent& {
    .inner { color: blue; }
    &.inner-concat { color: red; }
  }
}    

```

into

```css
div.concat .inner,
.parent div .inner,
section.concat .inner,
.parent section .inner {
  color:blue
}

div.concat.inner-concat,
.parent.inner-concat div,
section.concat.inner-concat,
.parent.inner-concat section {

  color:red
}
```


Bare selectors inside blocks create regular selection chains.

`@media` declarations can be nested as well but as of now there's no semantic checks done, which means that if you write something non-sensical it will be placed as is.

<div id="variables"></div>

#### Variables

```css
$!a_variable red;
$!another_variable 12;

div {
    color: <$a_variable$>;
    font-size: <$another_variable$>px;
}
```

##### into

```css
div {
    color: red;
    font-size: 12px;
}
```


#### Variables that create CSS variables on declaration

```css
$*!primary red;

div { color: <$primary$>; }
```

##### into

```css
:root {
      --primary: red;
}

div { color: red; }
```

#### Scoped Variables by file and set only if undefined variables 

##### file_1.cssex

```css
$!scope_variable_1 20px;
$!scope_variable_2 blue;

div { font-size: <$scope_variable_1$>; }

@include file_2.cssex;

#main {
      font-size: <$scope_variable_1$>;
      color: <$scope_variable_2$>;
}
```

##### file_2.cssex

```css
$()scope_variable_1 16px;
$!scope_variable_2 red;

.something {
      font-size: <$scope_variable_1$>;
      color: <$scope_variable_2$>;
}

@include file_3.cssex;
```

##### file_3.cssex

```css
$?scope_variable_1 12px;
$?scope_variable_2 green;

.something-2 {
      font-size: <$scope_variable_1$>;
      color: <$scope_variable_2$>;
}
```

##### into

```css
div { font-size: 20px; }
#main {
      font-size: 20px;
      color: red;
}

.something {
      font-size: 16px;
      color: red;
}

.something-2 {
      font-size: 20px;
      color: red;
}
```

Variables are literal values that can be used throughout a spreadsheet. They're inserted in place using the interpolation markers, `<$ variable_name $>`, or `$::variable_name`.
The declaration form is:

`$!name_of_variable literal_value;`

`literal_value` shouldn't be surround by quotes unless you want the quotes to be part of the value. It must always end with semi-colon followed by newline.

Using variables with `@include`'s directives allow one to share or create values that are overridable or specific to a stylesheet/include.

When a stylesheet declares an `@include` the current variables in scope will be made available on the child.
Child files (the one's `@include`d) can override the parent's variable value (after the child has been processed) if they declare them with `$!`,

You can otherwise limit this by declaring them with:
`$()` which scopes the variable locally so they do not become available to the parent afterwards, and you can also conditionally set them with:

`$?` which only sets them for the file if it isn't set in its scope yet. This allows you to create customisable themes, in that you can have a file(s) that specifies all colors, sizes and others, and then make the theme "components", set their needed values with `$?` which will populate those for the scope only if they haven't been declared previously, or override them in an included stylesheet with `$()`

You can also declare a variable with `$*!`, that does all the same but sets as well a CSS variable on the root element, with the same name as the variable declared, prefixed with `--`.

If you referr to a variable that hasn't been declared or not in scope you'll get an error.

<div id="assigns"></div>

#### Assigns

Assigns are the equivalent of variables but for Elixir values and they have the same options and scoping as that of variables, but instead of being declared with `$!`, `$()` and `$?`, they're declared with `@!`, `@()` and `@?`.

Variables are available inside EEx blocks or when calling functions. Since they can hold any elixir term they're great to create basic iterable structures to generate CSS based on repetition or iteration.

```css
@!colors %{
	 primary: "red",
	 secondary: "rgb(120, 255, 80)"
};

<%= for {color, val} <- @colors, reduce: "" do
    acc ->
    	acc <> """

	$*!#{color} #{val};

	.btn-#{color} {
	      	background-color: #{val};
	}

	"""
end %>

```

into

```css
.root {
      --primary: red;
      --secondary: rgb(120, 255, 80)
}

.btn-primary { background-color: red }
.btn-secondary { background-color: rgb(120, 255, 80) }
```

(while also creating both the `primary` and `secondary` variables that are accessible through the remaining spreadsheet and `@include`d children.

Inside EEx blocks they can be referred to with Elixir's `@assign_name` notation. When passing them to function as arguments they can be passed in as `@::assign_name`

So `@fn::name_of_function(@::colors)` would call that function with the argument being translated to the Elixir value of that variable.
As literal variables it will error if they're used without having been declared before or not available in scope.

The declaration form is:

`@!name_of_variable {:tuple, %{elixir: "map"}};`

It has to be terminated with semicolon followed by newline.


<div id="functions"></>

#### Functions

```elixir

@fn lighten_test(color, percentage) ->
    {:ok, %CSSEx.HSLA{l: %CSSEx.Unit{value: l} = l_unit} = hsla} = 
                                                       CSSEx.HSLA.new_hsla(color)

    {percentage, _} = Float.parse(percentage)

    new_l = 
      case l + percentage do
         n_l when n_l <= 100 and n_l >= 0 -> n_l
	 n_l when n_l > 100 -> 100
	 n_l when n_l < 0 -> 0
      end

    %CSSEx.HSLA{hsla | l: %CSSEx.Unit{l_unit | value: new_l}}
    |> to_string
end;

$!red red;
.test{color: @fn::lighten_test(<$red$>, 10)}
.test{color: @fn::lighten_test(#fdf, 10);}
```

##### into

```css
.test {
  color: hsla(0,100%,60%,1.0);
  color: hsla(300,7%,15%,1.0);
}
```

Functions can execute any code, and can receive an arbitrary block of content, that is made available in its body as a variable named, `ctx_content`. They need to evaluate to either `{:ok, binary | iodata}` or `binary | iodata`. You do not have access to functions, assigns, or variables inside functions, but you can pass them as arguments. The returned binary is also parsed before being inserted so you can also  make use of them on the returned result.
Inside a function you can call any Elixir code.

A function declaration has the following form:

```scss
@fn name_of_function(args, list) ->
   body
end;
```

`@fn` followed by the name and argument list followed by `->`. It must be terminated with `end`, semicolon followed by newline.

And a function call for that function would be `@fn::name_of_function(red, #ffffff)`.
Every function can take a last optional parent that is made available in the body of the function as `ctx_content`. In this case the call would be:

```scss
@fn::name_of_function(red, #ffffff,
   .content-made-available {
     &p.inside-name-of-function { color: blue; }
   }
)
```

When successfully called the result of evaluating it replaces the function call in the stylesheet and is parsed as if it was normal cssex code. This means that if a function returns content that includes  function calls, or interpolation, or declare variables, all those things are evaluated once it returns.


```scss
@fn enforce_size(what, size) ->
  "#{what}: #{size};" <>
  "min-#{what}: #{size};" <>
  "max-#{what}: #{size};"
end;

@fn enforce_wh(width, height) ->
  """
  @fn::enforce_size(width, #{width})
  @fn::enforce_size(height, #{height})
  """
end;

@fn enforce_square(size) ->
  """
  @fn::enforce_size(width, #{size})
  @fn::enforce_size(height, #{size})
  """
end;

@fn enforce_circle(size) ->
  """
  @fn::enforce_square(#{size})
  border-radius: 50%;
  """
end;

@fn my_squarer(element) ->
  """
  #{element} {
     #{ctx_content}
     @fn::enforce_square(20px)
  }
  """
end;
```

And then using for instance:

```scss
.section {
  @fn::my_squarer(&.inner, color: red;)
}
```

Results in:

```css
.section.inner{
  color:red;
  width:20px;
  min-width:20px;
  max-width:20px;
  height:20px;
  min-height:20px;
  max-height:20px;
}
```

Functions declared in a stylesheet (even `@included` children!) become available from then on. Further declarations of the same function name will override the previous one from then on.

<div id="eex"></>

#### EEx blocks


```elixir
@!breakpoints [
  sm: {"0px", "14px"},
  md: {"768px", "16px"},
  lg: {"992px", "18px"},
  xl: {"1200px", "20px"},
  xxl: {"1440px", "20px"},
];


<%= for {breakpoint, {_size, val}} <- @breakpoints, reduce: "" do
    acc ->
    	acc <> """
	
        .#{breakpoint}-section-title {
	   font-size: #{val};
	}

	"""
end %>
```

##### into

```css
.sm-section-title { font-size: 14px }
.md-section-title { font-size: 16px }
.lg-section-title { font-size: 18px }
// ... etc
```

An EEx block has to evaluate to either a binary (a string) or an iodata list. It's declared as Elixir blocks but always with the opening tag including the equal sign: `<%=`.
Inside EEx blocks you can use assigns with `@name_of_assign` syntax.

Right now you do not have access to either cssex variables or functions declared in the stylesheet but, again, the result of evaluating the block can contain any valid cssex construct which will be parsed afterwards in the context of the stylesheet as regular cssex before moving on to the remaining stylesheet.

<div id="comments"></>

#### Comments

```css
// you can use comments in both of these forms, all text will be stripped out
/* some

other {
   .commented-out part {

}
*/
```

<div id="reserved"></div>

#### Reserved Tokens

Using any of these outside of the syntax shown before can lead to errors:

```
&
@!
@?
@()
@::
$!
$*!
$?
$*?
$()
$*()
$::
@include
@fn
<% ....
<$ ....
//
/* ....
```

<div id="caveats"></div>

### Caveats

CSSEx does merging of selector declarations when they've been exactly specified (or resolved to) as the same.

For instance

```css
div { color: green; }
.sample { color: red; }
@include ../shared/samples.cssex;
```

And `../shared/samples.cssex`:

```css
$()tag div
#{tag} { background-color: white; color: orange; }
```

The final output will always have `div` declared first, and the attributes in their declaration order:

```css
div { color: green; background-color: white, color: orange }
.sample { color: red }
```

Instead of

```css
div { color: green; }
.sample { color: red; }
div { background-color: white, color: orange }
```

This means it can condense the final output. Right now it doesn't substitute repeated rules, but that might be added in the future.

If you want multiple declarations to not be merged right now the only possibility is to have different entry points that produce plain css files and use them with regular `@import` rules on a final css file that isn't parsed by cssex. 

The final output always follows this format:

```
@charset
@imports
**:root { variables }**
**all regular selectors and their rules**
@font-face
@media
@keyframes
```


<div id="installation"></div>

## Installation

This is an early and still incomplete release of this library, as of now it's not available in [hex.pm](https://hex.pm), it will be once the remaining baseline functionality is added ([roadmap](#roadmap)).

To install from github use:

```elixir

defp deps do
     [
        {:deployer, git: "https://github.com/mnussbaumer/cssex.git", only: [:dev], runtime: false}
     ]
end
```

<div id="usage"></div>

## Usage

To use it, add to your `dev.exs` configuration file:

```elixir

config :yourapp_web, CSSEx,
  entry_points: [{"priv/static/cssex/base.cssex", "priv/static/css/base.css"}]
```

##### Note

If you want to use other folder than priv you need to use an expandable path, e.g. the phoenix assets folder, you can do it by using, for instance in this case for an umbrella with a phoenix app:

```elixir

config :yourapp_web, CSSEx,
  entry_points: [
    {
      "../../../../apps/yourapp_web/assets/cssex/app.cssex",     ### entry
      "../../../../apps/yourapp_web/assets/css/app.css"          ### output
    }
  ]
```

Webpack can then use `app.css` as regularly.
You can specify as many entry points as wanted.

#### Adding the file watcher to your application supervision tree.

Finally add to your `yourapp_web` application file:

```elixir
defmodule YourAppWeb.Application do

   # ... other code

   def start(_type, _args) do
    children = [
      YourAppWeb.Telemetry,
      YourAppWeb.Endpoint,
      Supervisor.child_spec(%{id: CSSEx, start: {CSSEx, :start_link, [cssex_config()]}},
        type: :worker
      ) ## add this line
    ]

    opts = [strategy: :one_for_one, name: YourAppWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ... other code

  # add this
  def cssex_config() do
    Application.get_env(:yourapp_web, CSSEx)
    |> CSSEx.make_config(Application.app_dir(:yourapp_web))
  end
end
```

This will define an entry point file of `priv/static/cssex/base.cssex` which will output its parsed content into `priv/static/css/base.css`.
In this case you'll need to create the folder and cssex file as well. It will log errors if the file doesn't exist. If the folder doesn't exist you'll need to restart your app for it to pick up.

Now whenever you change something in the entry point or any of the files it depends on (`@include`) it will automatically recompile.

<div id="tasks"></div>

## Tasks

Besides the automatic file watcher for development purposes it's also included a task for processing cssex files into css files.

You can read [cssex.parser task](lib/mix/tasks/css.parser.ex) for other details.
The base syntax is:

```
# if using entry points defined in a config similar to the watcher
mix cssex.parser --c yourapp_web 

# if using manual entry points
mix cssex.parser --e path/to/file.cssex=path/to/output.css
```

<div id="internals"></div>

## Internals

Right now the library is mostly for use as regular pre-processor with a syntax that aids in building re-usable themes but it's been designed up 'till now to be expandable and to accomodate more use cases, such as dynamically feeding assigns, variables, functions, to templates, producing tables of css selectors and other details for post-processing, and generating on the fly CSS.

None of this is yet implemented in the form of a consistent api nor totally defined, but if you have a use case for any of those open an issue to discuss.

Other than that check the parser.ex to see how you can start an individual parser that can write to a file or return a binary with the result of the parsing.

<div id="roadmap"></div>

## Roadmap

- Additional functionality related with dynamic generation and visualisation of CSS in a structured format. This is mostly for use cases outside of pure pre-processing and more to do with tree-shaking, automatic vendor-prefixing, searchable CSS definitions, etc.

<div id="about"></div>

## About

![Cocktail Logo](logo/cocktail_logo.png?raw=true "Cocktail Logo")

[© rooster image in the cocktail logo](https://commons.wikimedia.org/wiki/User:LadyofHats)

<div id="copyright"></div>

## Copyright

```
Copyright [2021-∞] [Micael Nussbaumer]

Permission is hereby granted, free of charge, to any person obtaining a copy of this 
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify, 
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to 
permit persons to whom the Software is furnished to do so, subject to the following 
conditions:

The above copyright notice and this permission notice shall be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
