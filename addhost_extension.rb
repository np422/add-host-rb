# frozen_string_literal: true

# Extension module to add a function that calls a shell function to set another
# terminal profile, other background color to avoid mixing up remote and
# local shells, and then runs ssh with a the correct username for the remote
# site.
#
# The shell function name is set to the hostalias if present, otherwise
# from rules to generate a short and easy to type function name, based
# on the remote sites naming-convention so it's unique and predictable
#
module AddHostExtension
  attr_reader :extension_class

  # Actuall class that implements all the funky stuff
  class ZshSshFunctionAdder
    def initialize(ip:, hostname:, hostalias:, domain:, ssh:)
      @ip        = ip
      @hostname  = hostname
      @hostalias = hostalias
      @domain    = domain
      @ssh       = ssh
    end

    def do_whatever
      return unless @ssh
      @func_name = gen_func_name
      read_func_file
      remove_old_ssh_func
      rewrite_func_file
    end

    private

    def read_func_file
      @func_lines = File.open(File.expand_path('~/.funcs.zsh')).readlines
    end

    # Removes all lines between the hosts BEGIN/END comments in the lines from
    # the function file
    def remove_old_ssh_func
      outside_func = true
      @func_lines = @func_lines.select do |l|
        if outside_func
          # If the correct begin line is found, set the state var outside_func
          # to false and at the same time return false to mark the BEGIN line
          # as an unwanted line as well.
          (l =~ /BEGIN_SSH #{@hostname}/).nil? ? true : (outside_func = false)
        else
          # If the correct END line is found, alter state and returb false
          # as the END line also should be removed
          (l =~ /END_SSH #{@hostname}/).nil? || outside_func = true
          false
        end
      end
    end

    def rewrite_func_file
      File.open(File.expand_path('~/.funcs.zsh'), 'wt') do |f|
        f.puts @func_lines
        f.puts gen_shell_function
      end
    end

    # The shell function name should be easy/short to type and
    # easy to predict from the longer hostname.
    def gen_func_name
      return @hostalias unless @hostalias.empty?
      (_epr, @env, @func, @ab) = @hostname.split('-')
      @prefix = prefix_from_hostenv
      @suffix = suffix_from_abline
      "#{@prefix}#{@func}#{@suffix}"
    end

    def suffix_from_abline
      return '' if @ab.nil?
      "-#{@ab}"
    end

    def prefix_from_hostenv
      '' if @env.nil? || @env.empty?
      @env[0]
    end

    def gen_shell_function # rubocop:disable Metrics/MethodLength
      "
  # BEGIN_SSH #{@hostname}
  function #{@func_name}() {
      if [[ -n \"$ITERM_SESSION_ID\" ]]; then
          trap \"tab-reset\" INT EXIT
          tabc conextrade-ssh
          ssh -l pan #{@ip}
          tabc Default
          trap -
      else
          ssh -l pan #{@ip} $@
      fi
  }
  # END_SSH #{@hostname}
    "
    end
  end

  @extension_class = ZshSshFunctionAdder
end
