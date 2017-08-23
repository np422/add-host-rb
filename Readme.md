## add-host

A very small utility to fetch ip information from a remote DNS server and add it
to /etc/hosts and the ssh host-keys to ~/.ssh/known_hosts if the host responds to ssh.

Sometimes I connect with vpn to more than one remote site at the same time. I find it
to be less error prone to use the hosts file to resolve names compared to configure
multiple dns-servers with different opinions if a dns-query should give an ip-address
or NXDOMAIN as response to the query.

And it doesn't take very long time before the manual task of looking up ip-addresses
and adding them to /etc/hosts gets boring.

So I automated the process of finding the ip-address and adding an entry to the
hosts file, and as an added bonus the script it will get the ssh host-keys for
the host added and update ~/.ssh/known_hosts so already the first connectioin with
ssh can be done without any interactive yes responses.

#### USAGE
```
  add-host [-v|--verbose] [-a|--alias=ALIAS] -d|--domain=DOMAIN -s|--dns-server=DNS hostname_to_add
```
  The add-host command will resolve the ip-address of hostname_to_add by
  querying the dns-server specified with the option DNS.

  Any existing entry in /etc/hosts for the hostname_to_add will be removed and
  a new entry will be written to /etc/hosts for hostname_to_add

  A copy of the original /etc/hosts will be saved as /tmp/hosts-timestamp before
  any changes are made to the /etc/hosts file.

  If the hostname_to_add is connectable over ssh, any previously used ssh host
  keys for the hostname/ip will be removed from ~/.ssh/known_hosts and ssh
  host keys for host_to_add added to ~/.ssh/known_hosts.

  The environment variables AHDOMAIN, AHDNS will be used if --dns-server and
  --domain options aren't given. If you frequently use add-host you probably
  want to set the environment variables in your .bash_profile or similar.

  hostname_to_add should be short-form without a dommainname. The user running
  add-host needs sudo privlileges or have write-permissions on /etc/hosts.

  You can also add an ALIAS for hostname_to_add with the -a/--alias switch.

#### EXAMPLES
```
  $ add-host -d some.domain.com -s 10.20.20.11 prd-bapp-v021

  $ export AHDOMAIN=other.domain.org
  $ export ANDNS=172.16.14.0
  $ add-host -a ora1 oradb-vl001-ops-a
  $ add-host -a ora2 oradb-vl002-ops-b
```
#### OPTIONS
```
    -h, --help                       Display usage information
    -v, --verbose                    Print more output
    -d, --domain=DOMAIN              Use DOMAIN to resolve
    -s, --dns-server=DNS             Resolv host at DNS dns-server
    -a, --alias=ALIAS                Add an ALIAS for hostname_to_add
```

## Extending add-host with custom ruby

This was implemented mostly because you can, and because I thought it was fun.
I doubt that any sane person actually will attempt to use this function.

If the file ```~/.addhost_extension.rb``` or ```~/addhost_extension.rb``` exists they are
loaded using ```load``` and ```include AddHostExtension``` is attempted.

After /etc/hosts and known_hosts have been updated, a new extension object is
created with the following method-call

``` ruby
  extobj = AddHostExtension.extension_class.new(ip:        ip,
                                                hostname:  hostname,
                                                hostalias: hostalias,
                                                domain:    domain,
                                                ssh:       ssh)
```

Where hostname/hostalias is in short form, the AHDOMAIN is provided in domain
parameter and ssh is set to true if the host added was reachable over ssh,
ssh-keys were found and added to known_hosts

Then a call is made to the method ```extobj.do_whatever```, where an extension
can do pretty much whatever it wants to do with the information about the newly
added host.

I've included the extension that I actually use in the repo as an example. I
didn't think the stuff i put in addhost_extension.rb was generic enough to
include in the add-host command, but rather very specific to my personal
use-case.

The minimal_addhost_extension.rb can be used as starting point if you should
wish to try to write one yourself. That file is also included inline below:

``` ruby

module AddHostExtension
  attr_reader :extension_class


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

```
