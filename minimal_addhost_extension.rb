# frozen_string_literal: true

# Extension module
module AddHostExtension
  attr_reader :extension_class

  # Foo
  class MyExtensionClass
    def initialize(ip:, hostname:, hostalias:, domain:, ssh:)
      @ip        = ip
      @hostname  = hostname
      @hostalias = hostalias
      @domain    = domain
      @ssh       = ssh
    end

    def do_whatever
      debug_obj_vars
    end

    private

    def debug_obj_vars
      puts @ip
      puts @hostname
      puts @hostalias
      puts @domain
      puts @ssh
    end
  end

  @extension_class = MyExtensionClass
end
