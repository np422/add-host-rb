# frozen_string_literal: true

# Extension module to the add host program, save this file as
# ~/.addhost_extension.rb to call the .new and .do_whatever methods
# when the add-host command is executed.
#
module AddHostExtension
  attr_reader :extension_class

  # Name your class after purpose of extension, a planned improvement to
  # add-host is to allow usage of multiple extensions file in a directory
  # as long as the classes in the AddHostExtension namespace are unique.
  #
  class MyCoolExtensionClass
    # Constructor
    def initialize(ip:, hostname:, hostalias:, domain:, ssh:)
      @ip        = ip
      @hostname  = hostname
      @hostalias = hostalias
      @domain    = domain
      @ssh       = ssh
    end

    # This method will be called to perform whatever task
    # the extension wants to do
    def do_whatever
      debug_obj_vars
    end

    private

    def debug_obj_vars
      puts "The host #{@hostname}.#{@domain} has the ip-address #{@ip}, it can "
      puts "also be referenced by the alias #{@hostalias}.#{@domain} and the "
      puts 'host is' + (@ssh ? '' : ' not') + ' reachable with ssh'
    end
  end

  # Used by add-host to know what class to interact with.
  @extension_class = MyCoolExtensionClass
end
