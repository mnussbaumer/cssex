# CSSEx

A small pre-processing extension language for CSS written in Elixir.
Its main purpose is to provide a native Elixir pre-processor for CSS, in the vein of Sass/Scss.

<div align="center">
     <a href="#functionality">Functionality</a><p>|</p>
     <a href="#caveats">Caveats</a><p>|</p>
     <a href="#installation">Installation</a><p>|</p>
     <a href="#usage">Usage</a><p>|</p>
     <a href="#motivation">Motivation</a><p>|</p>
     <a href="#roadmap">Roadmap</a><p>|</p>
     <a href="#about">About</a><p>|</p>
     <a href="#copyright">Copyright</a>
</div>


<div id="functionality"></div>

#### Functionality:


##### Variables

```css
@!a_variable red;
@!another_variable 12;

div {
    color: <$a_variable$>;
    font-size: <$another_variable$>px;
}
```

###### into

```css
div {
    color: red;
    font-size: 12px;
}
```


##### Variables that create CSS variables on declaration

```css
@*!primary red;

div { color: <$primary$>; }
```

###### into

```css
:root {
      --primary: red;
}

div { color: red; }
```

##### Scoped Variables by file and set only if undefined variables 

###### file_1.cssex
```css
@!scope_variable_1 20px;
@!scope_variable_2 blue;

div { font-size: <$scope_variable_1$>; }

@include file_2.cssex;

#main {
      font-size: <$scope_variable_1$>;
      color: <$scope_variable_2$>;
}
```

###### file_2.cssex

```css
@()scope_variable_1 16px;
@!scope_variable_2 red;

.something {
      font-size: <$scope_variable_1$>;
      color: <$scope_variable_2$>;
}

@include file_3.cssex;
```

###### file_3.cssex

```css
@?scope_variable_1 12px;
@?scope_variable_2 green;

.something-2 {
      font-size: <$scope_variable_1$>;
      color: <$scope_variable_2$>;
}
```

###### into

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

These scope ruling might still be changed regarding the scoped workings and the undefined versions. Variables are inserted always using the interpolation markers, `<$ variable_name $>`.

##### Assigns

Assigns are as if variables and they have the same options and scoping as that of variables, but instead of being `@!`, `@*!`, `@()` and `@?`, they're identified by `%!`, `%()` and `%?`.
They can hold any valid elixir term and are only availble inside EEx blocks.

```css
%!colors %{
	 primary: "red",
	 secondary: "rgb(120, 255, 80)"
};

<%= for {color, val} <- @colors, reduce: [] do
    acc ->
    	["""
	.btn-#{color} {
	      	background-color: #{val};
	}
	""" | acc]
end %>
```

###### into

```css
.btn-primary { background-color: red; }
.btn-secondary { background-color: rgb(120, 255, 80); }
```

Assigns are passed down into `@includes` children files when being processed and can be overridden locally or conditionally with `()` or `?` instead of `!`.

An EEx block has to return either a binary (a String.t) or an iodata list. When parsing an EEx block the CSSEx parser first isolates the block (<%= ......everything %>) and then uses plain EEx eval while passing the assigns that are available to the block. The returned value can have `<$a_variable_outside$>` interpolation markers and those will be parsed after the block is returned, but not while being compiled with EEx.


<div id="caveats"></div>

##### Caveats

Due to the way it parses and builds output the final CSS files avoid a lot of repetition. It doesn't parse and insert the parsed result in place, instead it builds a table of selectors -> attributes and while parsing rules adds them to that selector. The order of the attributes for a selector is guaranteed, but the final layout of the selectors themselves is not.

This means that if you have two files, one:

```css
div { color: green; }
.sample { color: red; }
@include ../shared/samples.cssex;
```

And `../shared/samples.cssex`:

```css
div { background-color: white; color: orange; }
```

The final output for `div` will always have the attributes in their declaration order:
```css
div { color: green; background-color: white, color: orange}
```

But the position of this `div` selector in the final CSS is non deterministic. It means it could end up:
```css
div { color: green; background-color: white, color: orange}
.sample { color: red; }
```

Or

```css
.sample { color: red; }
div { color: green; background-color: white, color: orange}
```
This doesn't affect the CSS ruling though as that is defined by the selectors specificity and the attributes ordering, in this case `div` would always have its attribute `color` end up as being `orange` and never `green`.

The only exceptions are special CSS rules, which will appear in the following order always.

`@charset`
`@import`s
all regular selectors and their rules
`@font-face`s
`@media`s
`@keyframes`'


<div id="installation"></div>

### Installation

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

### Usage

To use it, add to your `dev.exs` configuration file:

```elixir

config :your_app_web, CSSEx,
  entry_points: [{"priv/static/cssex/base.cssex", "priv/static/css/base.css"}]
```

And to your `your_app_web` application file:

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
    Application.get_env(:your_app_web, CSSEx)
    |> CSSEx.make_config(Application.app_dir(:your_app_web))
  end
end
```

This will define an entry point file of `priv/static/cssex/base.cssex` which will output its parsed content into `priv/static/css/base.css`.

##### NOTE
The file watcher still needs some work, if you add the entry point without the file being existing it will crash (and log) and you'll need to restart the server, but a better strategy will be implemented in the future releases, the directory of the failed file will be set under watch and resume once the file appears.

<div id="motivation"></div>

### Motivation

I can't remember when I wrote pure CSS stylesheets without Sass/SCSS and I think they cover very well for the limitations CSS has (due to being something the browser needs to parse). It allows scaffolding entire themes and utility functions and write much more organised and intelligible CSS (the downsides are found in CSS as well, lack of organisation leads to style contamination, etc, but what it allows to do better is a net gain).

Sass/SCSS though, being a pre-processed language requires having `Ruby` and `libsass`, or `Node.js`/`NPM` along with (now) `dart-sass` (previously `libsass` as well). It's not a huge problem but it's an additional dependency that has always to be pulled in. As what I write is mostly Elixir I wanted a way of doing the sort of Sass pre-processing completely from Elixir land. Sass also has some limitations as in what it can do in terms of language by exposing a small subset of iteration constructs and data types.

I think that some times having access to a bigger array of tools can help and in that sense decided to instead of re-implementing `for` constructs and such using EEx would allow usage of any Elixir tool. Because it's a templating engine it also has a simple model to provide variables to the templates which then made the `assigns` idea straightforward to implement.

This all was prompted in first place by thinking about what a CMS and/or Static Site Generator written in Elixir would require - for what I envisioned a style processor that favoured the creation of easily customisable "themes" (including programatic customisation) made a lot of sense, and because it's something that can be useful for others, even if I don't end up writing the CMS/SSG, I decided to start by writing it.

It needs quite a bit of polishing and work but it already offers a programmatic interface (read the tests if you want to see) and a basic file-watching pre-processing pipeline to use in regular projects.

The chosen architecture lends itself very well also to integrate additional functionality, such as validation of CSS rules, rule-prefixing, tree-shaking, rules transformation and so on. It can also process in parallel as many entry points/files/binaries as required (but not files included from inside files obviously as those might depend on the parents and due to the variable/assigns scoping can bleed "upwards" and into siblings)

In terms of speed, although I haven't done extensive benchmarking as I want first to finish the basic roadmap, seems to be faster than dart-sass in small files in a significant way - not sure how it plays out with bigger files - but looks promising.

<div id="roadmap"></div>

### Roadmap

- Implement custom functions definition that cascade through the files as right now variables and assigns do. Still thinking on the syntax, probably something like:

```
@fn name(arg1, arg2) {
  //...
};
```

and called as:

```
div {
    color: @fn::name(red, blue);
}
```

- Basic functions such as: `lighten`, `darken`, etc.;
- Fix the current line and column error/warning reporting - this is mostly fixing what is already there (it's offset right now) and including the start line & col on each parsed selector, attribute, expression;
- Implement proper delimiter parsing, right now the parser doesn't check that each of (, [, {, ", ' have the proper ending char (always pairs), which can result in errors, such as using `"data[d-attr="something { color: red; }` being parsed and output as that invalid CSS selector.
- Mix task for parsing CSSEx files


With these I would consider it feature complete.
Additional things that depend on interest are:

- re-writing it completely in Erlang, but this requires a way of deciding how to interpret EEx blocks and passing assigns to Erlang blocks, everything else - structs can be records, parser function heads can use guards instead of meta-programming to be generated - translates pretty much 1:1 to Erlang;
- being able to wrap the whole thing in a downloadable package for use even without Erlang&Elixir installed or for projects not using Elixir - this is trickier as it would require ERTS to be shipped with the package - libsass+node-sass and dart+sass hover around 5mb unpacked each - a release+erts can probably be slimmed down but never to these values

<div id="about"></div>

### About

![Cocktail Logo](https://github.com/mnussbaumer/workforce/blob/master/logo/cocktail_logo.png?raw=true "Cocktail Logo")

[© rooster image in the cocktail logo](https://commons.wikimedia.org/wiki/User:LadyofHats)

<div id="copyright"></div>

### Copyright

```
Copyright [2021-∞] [Micael Nussbaumer]

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
