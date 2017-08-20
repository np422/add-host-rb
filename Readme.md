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
