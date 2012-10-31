defmodule Mix.SCM.Git do
  @behavior Mix.SCM
  @moduledoc false

  def format(opts) do
    [git: opts[:git]]
  end

  def format_lock(lock) do
    get_lock_rev lock
  end

  def accepts_options(opts) do
    cond do
      gh = opts[:github] ->
        opts /> Keyword.delete(:github) /> Keyword.put(:git, "https://github.com/#{gh}.git")
      opts[:git] ->
        opts
      true ->
        nil
    end
  end

  def checked_out?(opts) do
    File.dir?(File.join(opts[:path], ".git"))
  end

  def matches_lock?(opts) do
    opts[:lock] && File.cd!(opts[:path], fn ->
      opts[:lock] == get_lock(opts, true)
    end)
  end

  def equals?(opts1, opts2) do
    get_lock(opts1, false) == get_lock(opts2, false)
  end

  def checkout(opts) do
    path     = opts[:path]
    location = opts[:git]
    maybe_error System.cmd(%b[git clone --quiet --no-checkout "#{location}" "#{path}"])

    if checked_out?(opts) do
      File.cd! path, fn -> do_checkout(opts) end
    end
  end

  def update(opts) do
    File.cd! opts[:path], fn ->
      command = "git fetch --force --quiet"
      if opts[:tag] do
        command = command <> " --tags"
      end
      maybe_error System.cmd(command)
      do_checkout(opts)
    end
  end

  def clean(opts) do
    File.rm_rf opts[:path]
  end

  ## Helpers

  defp do_checkout(opts) do
    ref = get_lock_rev(opts[:lock]) || get_opts_rev(opts)
    maybe_error System.cmd("git checkout --quiet #{ref}")

    if opts[:submodules] do
      maybe_error System.cmd("git submodule update --init --recursive")
    end

    get_lock(opts, true)
  end

  defp get_lock(opts, fresh) do
    lock = if fresh, do: get_rev, else: get_lock_rev(opts[:lock])
    { :git, opts[:git], lock, get_lock_opts(opts) }
  end

  # We are supporting binaries for backwards compatibility
  defp get_lock_rev(lock) when is_binary(lock), do: lock
  defp get_lock_rev({ :git, _repo, lock, _opts }) when is_binary(lock), do: lock
  defp get_lock_rev(_), do: nil

  defp get_lock_opts(opts) do
    lock_opts = Enum.find_value [:branch, :ref, :tag], List.keyfind(opts, &1, 0)
    lock_opts = List.wrap(lock_opts)
    if opts[:submodules] do
      lock_opts ++ [submodules: true]
    else
      lock_opts
    end
  end

  defp get_opts_rev(opts) do
    if branch = opts[:branch] do
      "origin/#{branch}"
    else
      opts[:ref] || opts[:tag] || "origin/master"
    end
  end

  defp get_rev do
    check_rev System.cmd('git rev-parse --verify --quiet HEAD')
  end

  defp check_rev([]),   do: nil
  defp check_rev(list), do: check_rev(list, [])

  defp check_rev([h|t], acc) when h in ?a..?f or h in ?0..?9 do
    check_rev(t, [h|acc])
  end

  defp check_rev(fin, acc) when fin == [?\n] or fin == [] do
    Enum.reverse(acc) /> list_to_binary
  end

  defp check_rev(_, _) do
    nil
  end

  defp maybe_error(""),    do: :ok
  defp maybe_error(other), do: Mix.shell.error(other)
end