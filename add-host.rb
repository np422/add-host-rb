#!/usr/bin/env ruby

# frozen_string_literal: true

require 'tempfile'
require 'optparse'
require 'time'
require 'english'

class NoUpdateMethodAvailable < StandardError; end
class BackupFailed < StandardError; end

# Wrap all operations on /etc/hosts in a class
class HostsFile
  def initialize
    @host_lines = File.open('/etc/hosts').readlines
  end

  def remove_host_entries(hostname)
    @host_lines.select! do |line|
      (line =~ /#{hostname}/).nil?
    end
  end

  def add_host_entry(ip, fqdn, hostname)
    @host_lines.push "#{ip} #{fqdn} #{hostname}\n"
  end

  def backup(backup_filename)
    File.open(backup_filename, 'w') do |f|
      f.write @host_lines.join
    end
  rescue StandardError => e
    puts "Error caught when writing hosts file backup to #{backup_filename}:"
    puts e.to_s
    raise BackupFailed
  end

  def save
    if File.writable?('/etc/hosts')
      save_write
    elsif sudoer?
      save_sudo
    else
      raise NoUpdateMethodAvailable
    end
  end

  private

  def find_cmd(cmd)
    path_dirs = %w[/bin /sbin /usr/bin/ /usr/sbin /usr/loca/bin /usr/local/sbin]
    path_dirs.map { |p| "#{p}/#{cmd}" }.detect do |c|
      File.exist?(c) && File.executable?(c)
    end
  end

  def sudoer?
    cp_cmd = find_cmd('cp')
    `sudo -l #{cp_cmd} /etc/hosts /etc/hosts2 > /dev/null`
    $CHILD_STATUS.exitstatus.zero?
  end

  def to_tempfile
    tempfile = Tempfile.new('hostadd')
    tempfile.puts @host_lines.join('')
    tempfile.close
    tempfile
  end

  def replace_hosts_file_sudo(tempfile_path)
    cp_cmd = find_cmd('cp')
    `sudo #{cp_cmd} -f #{tempfile_path} /etc/hosts`
    chown_cmd = find_cmd('chown')
    `sudo #{chown_cmd} root /etc/hosts`
    chmod_cmd = find_cmd('chmod')
    `sudo #{chmod_cmd} 644 /etc/hosts`
  end

  def chgrp_hosts_file_sudo(gid)
    chgrp_cmd = find_cmd('chgrp')
    `sudo #{chgrp_cmd} #{gid} /etc/hosts`
  end

  def save_sudo
    tempfile = to_tempfile
    current_file_gid = File.stat('/etc/hosts').gid
    replace_hosts_file_sudo(tempfile.path)
    chgrp_hosts_file_sudo(current_file_gid)
  end

  def save_write
    File.open('/etc/hosts', 'wt') do |f|
      f.puts @host_lines.join
    end
  end
end

def update_hosts(ip, fqdn, host, backup)
  HostsFile.new do |hostsfile|
    hostsfile.backup("/tmp/hosts-#{Time.now.to_i}") if backup
    hostsfile.remove_host_entries(host)
    hostsfile.add_host_entry(ip, fqdn, host)
    hostfile.save
  end
rescue StandardError => e
  puts 'Error when updating hosts file'
  puts "Error: #{e}"
  exit 1
end

def remove_ssh_keys(hostlist)
  hostlist.each do |host|
    `ssh-keygen -q -R #{host} >/dev/null 2>&1`
  end
end

def add_ssh_keys(keyscan_template, hostlist)
  File.open('/Users/niklas/.ssh/known_hosts', 'a') do |f|
    hostlist.each do |host|
      keyscan_data = keyscan_template.gsub('_HOST_', host)
      f.puts keyscan_data
    end
  end
end

def update_ssh_keys(keyscan_template, hostlist, verbose)
  puts "Removing '#{hostlist.join('\',\'')}' from ~/.ssh/known_hosts" if verbose
  remove_ssh_keys(hostlist)
  puts 'Updating ~/.ssh/known_hosts using ssh-keyscan' if verbose
  add_ssh_keys(keyscan_template, hostlist)
end

def mkhostlist(ip, host_fqdn, hostname, alias_fqdn, hostalias)
  hostlist = [ip, host_fqdn, hostname]
  hostlist.push alias_fqdn unless alias_fqdn.nil?
  hostlist.push hostalias unless hostalias.nil?
  hostlist
end

# rubocop:disable LineLength, MethodLength
def banner
  "\e[1m\e[4mUSAGE\e[0m

  \e[1madd-host [-v|--verbose] [-a|--alias=ALIAS] -d|--domain=DOMAIN -s|--dns-server=DNS hostname_to_add\e[0m

  The add-host command will resolve the ip-address of hostname_to_add by querying
  the dns-server specified with the option DNS.

  Any existing entries in /etc/hosts for the hostname_to_add will be removed and
  a new entry will be written to /etc/hosts for hostname_to_add

  A copy of the original /etc/hosts will be saved as /tmp/hosts-timestamp before
  any changes are made to the /etc/hosts file.

  If the hostname_to_add is connectable over ssh, all existing ssh host keys for
  the hostname/ip will be removed from ~/.ssh/known_hosts and the ssh host keys
  used by host_to_add will be added to ~/.ssh/known_hosts.

  The environment variables AHDOMAIN, AHDNS will be used if --domain or
  --dns-server options aren't given. If you frequently use add-host you probably
  want to set the environment variables in your .bash_profile or similar.

  hostname_to_add should be short-form, without a dommainname. The user running
  add-host needs sudo privlileges or must have write-permissions on /etc/hosts.

  You can also add an ALIAS for hostname_to_add with the -a/--alias switch.

\e[1m\e[4mEXAMPLES\e[0m

  $ add-host -d some.domain.com -s 10.20.20.11 prd-bapp-v021

  $ export AHDOMAIN=other.domain.org
  $ export ANDNS=172.16.14.0
  $ add-host -a ora1 oradb-vl001-ops-a
  $ add-host -a ora2 oradb-vl002-ops-b

\e[1m\e[4mOPTIONS\e[0m

"
end
# rubocop:enable LineLength, MethodLength

def add_more_switches!(parser, options)
  parser.on('-s DNS', '--dns-server=DNS', 'Resolv host using DNS server') do |s|
    options[:dns] = s
  end
  parser.on('-a ALIAS', '--alias=ALIAS', 'Add ALIAS for hostname_to_add') do |a|
    options[:alias] = a
  end
end

def add_switches_get_options!(parser)
  options = {}
  parser.on('-h', '--help', 'Display usage info') { options[:help] = true }
  parser.on('-v', '--verbose', 'Print more output') { options[:verbose] = true }
  parser.on('-d DOMAIN', '--domain=DOMAIN', 'Use DOMAIN to resolve') do |d|
    options[:domain] = d
  end
  add_more_switches!(parser, options)
  options
end

def options_from_env!(options)
  options[:dns] = ENV['AHDNS'] if options[:dns].nil?
  options[:domain] = ENV['AHDOMAIN'] if options[:domain].nil?
end

def switch_please
  optparser = OptionParser.new
  optparser.banner = banner
  options = add_switches_get_options! optparser
  optparser.parse!
  options_from_env! options
rescue OptionParser::InvalidOption
  puts optparser
  exit 1
else
  [optparser, options]
end

# Main program start

(parser, options) = switch_please
host = ARGV[0]

if options[:help]
  puts parser.help
  exit 0
elsif options[:dns].nil?
  puts 'No dns server, use -s|--dns-server= or environment variable AHDNS'
  exit 1
elsif  options[:domain].nil?
  puts 'No domain, use -d|--domain=DOMAIN or environment variable AHDNS'
  exit 1
elsif host.nil?
  puts 'No host to add given.'
  exit 1
end

dns        = options[:dns]
domain     = options[:domain]
verbose    = options[:verbose]
hostalias  = options[:alias]
alias_fqdn = options[:alias].nil? ? nil : "#{hostalias}.#{domain}"

host_fqdn  = "#{host}.#{domain}"
dig_cmd    = "dig +short +retry=1 +time=1 @#{dns} #{host_fqdn}"
dig_output = `#{dig_cmd}`

if ($CHILD_STATUS.exitstatus != 0) || dig_output.empty?
  puts "Couldn't resolv #{host_fqdn} using dns-server #{dns}"
  puts "Command used to resolve was: #{dig_cmd}" if verbose
  exit 1
end

dig_output.scan(/\b(?:\d{1,3}\.){3}\d{1,3}\b/) do |ip|
  puts "Adding '#{ip} #{host_fqdn} #{host}' to /etc/hosts" if verbose
  update_hosts(ip, host_fqdn, host, true)

  msg = "Also adding alias '#{ip} #{alias_fqdn} #{hostalias}' to /etc/hosts"
  puts msg if verbose && !hostalias.nil?
  update_hosts(ip, alias_fqdn, hostalias, false) unless hostalias.nil?

  keyscan_output = `ssh-keyscan -T 2 #{host_fqdn} 2>/dev/null`
  if keyscan_output.empty? || $CHILD_STATUS.exitstatus != 0
    puts 'Not adding ssh host keys' if verbose
    puts "Can't to connect to #{host_fqdn} using ssh-keyscan" if verbose
  else
    keyscan_template = keyscan_output.gsub(host_fqdn, '_HOST_')
    hostlist = mkhostlist(ip, host_fqdn, host, alias_fqdn, hostalias)
    update_ssh_keys(keyscan_template, hostlist, verbose)
  end
end

at_exit do
  begin
    ObjectSpace.each_object(File) do |f|
      f.close unless f.closed?
    end
  rescue StandardError => e
    puts e.to_s
  end
end
