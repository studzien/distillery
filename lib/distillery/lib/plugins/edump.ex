defmodule Distillery.Plugins.Edump do
  @moduledoc """
  A release plugin for Distillery which will provide a command to inspect crash dump
  files at the command line. To use, you'll need to add the following dependency to your
  project:

      {:edump, github: "bitwalker/edump"}

  Then, just add the plugin to your release definition:

      release :myapp do
        ...
        plugin Distillery.Plugins.Edump
      end

  Now, when you build a release, the command will be included, and can be used like so:

      bin/myapp edump
      Usage: edump [-h] [-v] [<task>]

        -h, --help     Print this help.
        -v, --version  Show version information.
        <task>         Task to run: index, graph, info, try

  As you can see, you have a few different options. Check the README of the `edump` project for more
  details, but as a brief whirlwind tour:

  The `index` command will index the crash dump, this is important for performance, as large crash dumps
  can be very hard to read all at once. It is recommended you run this against the crash dump first.

  The `graph` command can be used to produce a DOT graph of processes. See the `edump` README for more.

  The `info` command is the one you will most likely be interested in, and by default produces a basic summary,
  including why the node crashed, memory usage, number of processes/ports, etc. You can drill in to different aspects
  of the data by passing `--info=<type>`, it is `basic` by default, and can also accept `processes`. This is still a
  work in progress, so that's the extent of the support at the moment.

  The `try` command currently doesn't provide anything of real value, except that it will show the actual Erlang error
  returned when trying to parse the crash dump, if for some reason you are unable to do so.

  The actual author of the project is `archaelus`, you can find the original repository for the project at
  https://github.com/archaelus/edump. My fork is simply to make it work as a dependency of a Mix project.
  """
  use Mix.Releases.Plugin

  def before_assembly(%Release{} = release) do
    with %Mix.Dep{} = edump <- get_edump_dep(),
         {:ok, escript_path} <- get_escript_path(edump),
         modified_release <- add_plugin_artifacts(release, escript_path) do
      modified_release
    else
      _ ->
        release
    end
  end

  defp add_plugin_artifacts(%Release{profile: profile} = release, escript_path) do
    priv_dir = "#{:code.priv_dir(:distillery)}"
    command_path = Path.join([priv_dir, "plugins", "edump.sh"])
    overlays =
      [{:copy, escript_path, "releases/<%= release.version %>/edump"},
       {:copy, command_path, "releases/<%= release.version %>/commands/edump.sh"}
       | profile.overlays]
    %{release | :profile => %{profile | :overlays => overlays}}
  end

  defp get_edump_dep() do
    Mix.Dep.loaded_by_name([:edump], [])
  rescue
    Mix.Error ->
      nil
  else
    [edump] ->
      edump
  end

  defp get_escript_path(edump) do
    mix_home = System.get_env("MIX_HOME")
    rebar3 = Path.join(mix_home, "rebar3")
    proceed? =
      if File.exists?(rebar3) do
        true
      else
        debug "edump: rebar3 is required but missing, attempting to install it.."
        case System.cmd("mix", ["local.rebar", "--force"]) do
          {_, 0} ->
            debug "edump: Successfully installed rebar3"
            true
          _ ->
            warn "edump: Unable to succesfully install rebar3!"
            false
        end
      end
    if proceed? do
      Mix.Dep.in_dependency(edump, fn _ ->
        debug "edump: Building edump escript.."
        case System.cmd(rebar3, ["escriptize"]) do
          {_, 0} ->
            [{edump_path, _}] = Mix.Dep.source_paths(edump)
            escript_path = Path.join([edump_path, "_build", "default", "bin", "edump"])
            if File.exists?(escript_path) do
              debug "edump: Escript successfully built!"
              {:ok, escript_path}
            else
              warn "edump: Building escript succeeded, but output is not where it is expected, skipping.."
              nil
            end
          {output, _} ->
            debug output
            warn "edump: Failed to build edump escript!"
            nil
        end
      end)
    else
      nil
    end
  end
end
