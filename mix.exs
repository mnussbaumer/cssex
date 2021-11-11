defmodule Cssex.MixProject do
  use Mix.Project

  def project do
    [
      app: :cssex,
      version: "0.6.9",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "CSSEx",
      source_url: "https://github.com/mnussbaumer/cssex",
      homepage_url: "https://hexdocs.pm/cssex/readme.html",
      docs: [
        main: "CSSEx",
        extras: ["README.md"]
      ],
      description: "A CSS preprocessor written in Elixir",
      package: [
        licenses: ["MIT"],
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
      {:file_system, "~> 0.2"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end
end
