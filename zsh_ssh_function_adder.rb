# frozen_string_literal: true

# Extension module to add a shell function to my zsh startup scripts
# The function added activates another terminal profile with a different
# background color to avoid mixing up remote and local shells.
# After setting the terminal profile the scripts then starts ssh to the
# remote host with the
#
# The shell function name is set to the hostalias if hostalias is present,
# otherwise hard-coded rules are used to generate a short and easy to type
# function name. The rules are based on the remote sites naming-convention
# so the function name will be unique, predictable and easy to remember.
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
      # Don't add functions to connect to windows hosts without ssh-server
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

    # This removes all lines between the added hosts BEGIN/END comments in the
    # current func-files content.
    def remove_old_ssh_func
      outside_func = true
      @func_lines = @func_lines.select do |l|
        if outside_func
          # If the correct begin line is found, set the state variable
          # outside_functo false and also return false to mark the BEGIN line
          # as an unwanted
          (l =~ /BEGIN_SSH #{@hostname}/).nil? ? true : (outside_func = false)
        else
          # If the correct END line is found, set the state variable outside
          # func to true, but return false as the END line also should be
          # removed
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

    def gen_func_name
      return @hostalias unless @hostalias.empty?
      (_epr, @env, @func, @ab) = @hostname.split('-')
      @prefix = prefix_from_hostenv
      @suffix = suffix_from_ab_line
      "#{@prefix}#{@func}#{@suffix}"
    end

    def suffix_from_ab_line
      return '' if @ab.nil?
      "-#{@ab}"
    end

    def prefix_from_hostenv
      '' if @env.nil? || @env.empty?
      @env[0]
    end

    # The shell function to add.
    # the functions tab-reset and tabc are defined in an other place
    # in the collection of zsh startup-files.
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
