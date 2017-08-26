#!/usr/bin/env ruby

# frozen_string_literal: true

require 'tempfile'
require 'optparse'
require 'time'
require 'english'

class NoUpdateMethodAvailable < StandardError; end
class BackupFailed < StandardError; end
class SshKeyRemovalError < StandardError; end
class SshKeyWriteError < StandardError; end

# Avoid re-checking verbose option on every puts of a informational message to user
module Out
  @verbose = true

  class << self
    attr_accessor :verbose
  end

  def self.put(str)
    puts str if @verbose
  end
end

# Wrap all operations on /etc/hosts in a class
class HostFile
  # A static method for easier usages, it wraps all the operations needed
  # to update /etc/hosts
  def self.add(ip:, name_fqdn:, hostname:)
    hostsfile = HostFile.new
    hostsfile.remove_host_entries(hostname: hostname)
    hostsfile.add_host_entry(ip: ip, name_fqdn: name_fqdn, hostname: hostname)
    hostsfile.save
  rescue StandardError => error
    puts 'Error when updating hosts file'
    puts "Error: #{error}"
    exit 1
  end

  # Backup should only be made on the first save of /etc/hosts per run of
  # add-host, use class variable @@backup to know if we already have done
  # a backup this time.
  @@backup = false

  def initialize
    @host_lines = File.open('/etc/hosts').readlines
  end

  def remove_host_entries(hostname:)
    @host_lines.reject! { |line| line.match(/#{hostname}/) }
  end

  def add_host_entry(ip:, name_fqdn:, hostname:)
    @host_lines.push "#{ip} #{name_fqdn} #{hostname}\n"
  end

  def save
    backup_content unless @@backup
    if File.writable?('/etc/hosts')
      save_write
    elsif sudoer?
      save_sudo
    else
      raise NoUpdateMethodAvailable
    end
  end

  def backup_content
    return if @@backup
    backup_filename = "/tmp/hosts-#{Time.now.to_i}"
    File.open(backup_filename, 'w') do |file|
      file.write @host_lines.join
    end
    @@backup = true
  rescue StandardError => error
    puts "Error caught when writing hosts file backup to #{backup_filename}:"
    puts error.to_s
    raise BackupFailed
  end

  private

  def sudoer?
    cp_cmd = find_cmd(cmd: 'cp')
    `sudo -l #{cp_cmd} /etc/hosts /etc/hosts2 > /dev/null`
    $CHILD_STATUS.exitstatus.zero?
  end

  def replace_hosts_file_sudo(tempfile_path:)
    cp_cmd = find_cmd(cmd: 'cp')
    `sudo #{cp_cmd} -f #{tempfile_path} /etc/hosts`
    chown_cmd = find_cmd(cmd: 'chown')
    `sudo #{chown_cmd} root /etc/hosts`
    chmod_cmd = find_cmd(cmd: 'chmod')
    `sudo #{chmod_cmd} 644 /etc/hosts`
  end

  def chgrp_hosts_file_sudo(gid:)
    chgrp_cmd = find_cmd(cmd: 'chgrp')
    `sudo #{chgrp_cmd} #{gid} /etc/hosts`
  end

  def save_sudo
    tempfile = lines_to_tempfile(lines: @host_lines)
    current_file_gid = File.stat('/etc/hosts').gid
    replace_hosts_file_sudo(tempfile_path: tempfile.path)
    chgrp_hosts_file_sudo(gid: current_file_gid)
  end

  def save_write
    File.open('/etc/hosts', 'wt') do |f|
      f.puts @host_lines.join
    end
  end
end

# Utility functions mostly used by class HostFile

def lines_to_tempfile(lines:)
  tempfile = Tempfile.new('add-host-rb')
  tempfile.puts lines.join('')
  tempfile.close
  tempfile
end

def find_cmd(cmd:)
  path_dirs = %w[/bin /sbin /usr/bin/ /usr/sbin /usr/loca/bin /usr/local/sbin]
  path_dirs.map { |path| "#{path}/#{cmd}" }.detect do |cmd_path|
    File.exist?(cmd_path) && File.executable?(cmd_path)
  end
end

# Wrap ssh host-key manipulation into a utility class
class SshKeysManipulator
  def initialize(*hostnames)
    @ssh_hosts = []
    @ssh_hosts.concat hostnames.reject(&:empty?)
    keyscan
    self
  end

  def update_known_hosts
    return false if @keyscan_template.empty?
    Out.put "Removing '#{@ssh_hosts.join('\',\'')}' from ~/.ssh/known_hosts"
    remove_ssh_keys
    Out.put 'Updating ~/.ssh/known_hosts using keys found by ssh-keyscan'
    add_ssh_keys
    true
  end

  private

  def keyscan
    Out.put 'Scanning for ssh host-keys'
    scan_host = @ssh_hosts.first
    keyscan_output = `ssh-keyscan -T 2 #{scan_host} 2>/dev/null`
    if keyscan_output.empty? || $CHILD_STATUS.exitstatus != 0
      Out.put "Can't to connect to #{scan_host} using ssh-keyscan,
               no modifications will be made to the known-hosts file"
      @keyscan_template = ''
    else
      @keyscan_template = keyscan_output.gsub(scan_host, '_HOST_')
    end
  end

  def remove_ssh_keys
    return if @keyscan_template.empty?
    @ssh_hosts.each do |host|
      Out.put "Removing #{host} from knonw-hosts"
      `ssh-keygen -q -R #{host} >/dev/null 2>&1`
      $CHILD_STATUS.exitstatus != 0 && raise(SshKeyRemovalError,
                                             "Error while running #{cmd}")
    end
  end

  def add_ssh_keys
    return if @keyscan_template.empty?
    File.open(File.expand_path('~/.ssh/known_hosts'), 'at') do |f|
      @ssh_hosts.each do |host|
        Out.put "Adding #{host} to known_hosts"
        keyscan_data = @keyscan_template.gsub('_HOST_', host)
        f.puts keyscan_data
      end
    end
  rescue StandardError => e
    puts "Error while updating ~/.ssh/known_hots: #{e}"
    raise SshKeyWriteError
  end
end

# Here be extensions
module CurrentExtensions
  attr_reader :extension_class_list
  @@extension_classes = []

  def self.load_extensions
    Out.put 'Looking for extensions'
    Dir.glob(File.expand_path('~/.addhost_extensions.d/*.rb')).each do |path|
      load_extension_file(file: path)
    end
    Out.put 'Loaded extensions:'
    @@extension_classes.each { |c| Out.put c.to_s }
  rescue StandardError => err
    puts "Error while loading extension, err = #{err}"
    puts 'Skipping extensions execution this time'
    puts err.backtrace
    @@extension_classes = []
  end

  def self.loaded?
    return !AddHostExtension.nil?
  rescue NameError
    return false
  end

  def self.run(ip:, hostname:, hostalias:, domain:, ssh:)
    return if @@extension_classes.length.zero? || !loaded?
    @@extension_classes.each do |extension|
      Out.put "Running extension #{extension}"
      extobj = extension.new(ip:        ip,
                             hostname:  hostname,
                             hostalias: hostalias,
                             domain:    domain,
                             ssh:       ssh)
      extobj.do_whatever
    end
  end

  def self.load_extension_file(file:)
    Out.put "Loading extension file: #{file}"
    load file.to_s
    Out.put 'File loaded'
    include AddHostExtension
    @@extension_classes << AddHostExtension.class_eval { @extension_class }
    Out.put 'Module class saved: '
    Out.put @@extension_classes.last.to_s
  end
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
  $ export AHDNS=172.16.14.0
  $ add-host -a ora1 oradb-vl001-ops-a
  $ add-host -a ora2 oradb-vl002-ops-b

\e[1m\e[4mOPTIONS\e[0m

"
end
# rubocop:enable LineLength, MethodLength

def add_more_switches!(parser:, options:)
  parser.on('-s DNS', '--dns-server=DNS', 'Resolv host using DNS server') do |s|
    options[:dns] = s
  end
  parser.on('-a ALIAS', '--alias=ALIAS', 'Add ALIAS for hostname_to_add') do |a|
    options[:alias] = a
  end
end

def add_switches_get_options!(parser:)
  options = {}
  parser.on('-h', '--help', 'Display usage info') { options[:help] = true }
  parser.on('-v', '--verbose', 'Print more output') { options[:verbose] = true }
  parser.on('-d DOMAIN', '--domain=DOMAIN', 'Use DOMAIN to resolve') do |d|
    options[:domain] = d
  end
  add_more_switches!(parser: parser, options: options)
  options
end

def options_from_env!(options:)
  options[:dns] = ENV['AHDNS'] if options[:dns].nil?
  options[:domain] = ENV['AHDOMAIN'] if options[:domain].nil?
end

def switch_please
  optparser = OptionParser.new
  optparser.banner = banner
  options = add_switches_get_options!(parser: optparser)
  optparser.parse!
  options_from_env!(options: options)
rescue OptionParser::InvalidOption
  puts optparser
  exit 1
else
  [optparser, options]
end

# Main program starts here, with option parsing and input validation

include Out
include CurrentExtensions

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

dns         = options[:dns]
domain      = options[:domain]
verbose     = options[:verbose].nil? ? false : options[:verbose]
Out.verbose = verbose
hostalias   = options[:alias].nil? ? '' : options[:alias]
alias_fqdn  = options[:alias].nil? ? '' : "#{hostalias}.#{domain}"
host_fqdn   = "#{host}.#{domain}"

# And here starts the main-program stuff that actually does something

dig_cmd     = "dig +short +retry=1 +time=1 @#{dns} #{host_fqdn}"
dig_output  = `#{dig_cmd}`

if ($CHILD_STATUS.exitstatus != 0) || dig_output.empty?
  puts "Couldn't resolv #{host_fqdn} using dns-server #{dns}, can't continue."
  Out.put "Command used to resolve was: #{dig_cmd}"
  Out.put "Message from command was:\n#{dig_output}"
  exit 1
end

# Match dig output against an ip-address regexp to ensure
# that we get the ip-address from the reply and not a CNAME pointer
# or something else we don't expect.
dig_output.scan(/\b(?:\d{1,3}\.){3}\d{1,3}\b/) do |ip|
  Out.put "Adding '#{ip} #{host_fqdn} #{host}' to /etc/hosts"
  HostFile.add(ip: ip, name_fqdn:  host_fqdn, hostname: host)

  Out.put "Also adding alias '#{ip} #{alias_fqdn} #{hostalias}' to /etc/hosts" unless hostalias.empty?
  HostFile.add(ip: ip, name_fqdn:  alias_fqdn, hostname:   hostalias) unless hostalias.empty?

  ssh_editor = SshKeysManipulator.new(ip, host_fqdn, host,
                                      alias_fqdn, hostalias)
  host_got_ssh = ssh_editor.update_known_hosts

  CurrentExtensions.load_extensions
  CurrentExtensions.run(ip: ip, hostname: host, hostalias: hostalias, domain: domain, ssh: host_got_ssh)
end

# Close all files even in the case of premature exit due to errors
at_exit do
  begin
    ObjectSpace.each_object(File) do |f|
      f.close unless f.closed?
    end
  rescue StandardError => e
    puts e.to_s
  end
end
