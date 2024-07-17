defmodule Cssex.MixProject do
  use Mix.Project

  def project do
    [
      app: :cssex,
      version: "1.0.1",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "CSSEx",
      source_url: "https://github.com/mnussbaumer/cssex",
      homepage_url: "https://hexdocs.pm/cssex/readme.html",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ],
      description: "A CSS preprocessor written in Elixir",
      package: [
        licenses: ["MIT"],
        exclude_patterns: [~r/.*~$/, ~r/#.*#$/],
        links: %{
          "github/readme" => "https://github.com/mnussbaumer/cssex"
        }
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:file_system, "~> 1.0"},
      {:ex_doc, "~> 0.32", only: :dev, runtime: false}
    ]
  end
end
