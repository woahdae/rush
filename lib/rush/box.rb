# A rush box is a single unix machine - a server, workstation, or VPS instance.
#
# Specify a box by hostname (default = 'localhost').	If the box is remote, the
# first action performed will attempt to open an ssh tunnel.	Use square
# brackets to access the filesystem, or processes to access the process list.
#
# Example:
#
#		local = Rush::Box.new('localhost')
#		local['/etc/hosts'].contents
#		local.processes
#
class Rush::Box
	attr_reader :host, :connection

	# Instantiate a box.	No action is taken to make a connection until you try
	# to perform an action.	 If the box is remote, an ssh tunnel will be opened.
	# Specify a username with the host if the remote ssh user is different from
	# the local one (e.g. Rush::Box.new('user@host')).
	def initialize(host='localhost', *options)
		options = options.to_options_hash
		if host == 'localhost'
			@connection = Rush::Connection::Local.new
			@host = host
		elsif options[:rushd]
			@connection = Rush::Connection::Rushd.new(host)
		else # a remote host
			ssh_options = {}
			ssh_options[:password] = options.delete(:password)
			user, host = get_host_and_user(host, options)
			ssh_options[:user] = user
			ssh_options[:host] = host
			ssh_options[:port] = options.delete(:port)
			@connection = Rush::Connection::SSH.new(self, ssh_options)
			@host = host
		end
		
		initialize_options(options)		
	end

	##### File operations #####
	
	##
	# Methods that have the potential to operate on more than one box (ex. cp)
	# should be written here, in box.rb, as they have to take into account
	# both local and remote possibilities in one method. For methods that
	# just operate either locally or remotely (ex. ls), those should be written
	# in local_box.rb or remote_box.rb.
	# 
	# For reference, note that a cross-box method has at most 5 possibilites
	# to take into account:
	# 1. local-local
	# 2. local-remote (uploading)
	# 3. remote-local (downloading)
	# 4. remote-remote, same server
	# 5. remote-remote, cross-server
	# 
	# Not all cross-box methods need to handle all of them, but some do (ex. cp)
	##
	
	# TODO: DRY up mv/cp
	# the move method was copy-pasted from copy. Not dry, but easy.

	##
	# Copies a file or directory from a source to a destination, allowing any
	# combination of src and dst:
	# 
	# 1. local-local
	# 2. local-remote (uploading)
	# 3. remote-local (downloading)
	# 4. remote-remote, same server
	# 5. remote-remote, cross-server
	# === Parameters
	# [+src+] Either a Rush::File or Rush::Dir object representing
	#					the existing file to copy.
	# [+dst+] Either a Rush::File or Rush::Dir object representing
	#					the new destination.
	# === Returns
	# A Rush::File or Rush::Dir object representing the new
	# file or directory
	# === Raises
	# * Rush::DoesNotExist if the source or destination path is bad
	def copy(src, dst)
		# TODO: make cp able to handle strings, where it will create an entry based
		# on the box it's run from.
		
		if !(src.kind_of?(Rush::Entry) && dst.kind_of?(Rush::Entry))
			raise ArgumentError, "must operate on Rush::Dir or Rush::File objects"
		end
		
		# 5 cases:
		# 1. local-local
		# 2. local-remote (uploading)
		# 3. remote-local (downloading)
		# 4. remote-remote, same server
		# 5. remote-remote, cross-server
		if src.box == dst.box # case 1 or 4
			if src.box.remote? # case 4
				src.box.ssh.exec!("cp -r #{src.full_path} #{dst.full_path}") do |ch, stream, data|
					if stream == :stderr
						raise Rush::DoesNotExist, stream
					end
				end
			else # case 1
				FileUtils.cp_r(src.full_path, dst.full_path)
			end
		else # case 2, 3, or 5
			if src.local? && !dst.local? # case 2
				# We use the connection on the remote machine to do the upload
				dst.box.ssh.scp.upload!(src.full_path, dst.full_path, :recursive => true)
			elsif !src.local? && dst.local? # case 3
				# We use the connection on the remote machine to do the download
				src.box.ssh.scp.download!(src.full_path, dst.full_path, :recursive => true)
			else # src and dst not local, case 5
				remote_command = "scp #{src.full_path} #{dst.box.user}@#{dst.box.host}:#{dst.full_path}"
				# doesn't matter whose connection we use
				src.box.ssh.exec!(remote_command) do |ch, stream, data|
					if stream == :stderr
						raise Rush::DoesNotExist, stream
					end
				end
			end
		end

		# TODO: use tar for cross-server transfers.
		# something like this?:
		# archive = from.box.read_archive(src)
		# dst.box.write_archive(archive, dst)

		new_full_path = dst.dir? ? "#{dst.full_path}#{src.name}" : dst.full_path
		src.class.new(new_full_path, dst.box)
	rescue Errno::ENOENT
		raise Rush::DoesNotExist, File.dirname(to)
	rescue RuntimeError
		raise Rush::DoesNotExist, from
	end
	alias :cp :copy

	##
	# Moves a file or directory from a source to a destination on the same server,
	# i.e local-local or remote-remote (on the same server).
	# 
	# (the reason for this is that if the remote copy were to silently fail, we
	# would then inadventently delete the only copy of it)
	# === Parameters
	# [+src+] Either a Rush::File or Rush::Dir object representing
	#					the existing file to move.
	# [+dst+] Either a Rush::File or Rush::Dir object representing
	#					the new destination.
	# === Returns
	# A Rush::File or Rush::Dir object representing the new
	# file or directory
	# === Raises
	# * RuntimeError if the move would span across servers.
	# * Rush::DoesNotExist if the source or destination path is bad
	def move(src, dst)
		# TODO: make mv able to handle strings, where it will create an entry based
		# on the box it's run from.
		
		if !(src.kind_of?(Rush::Entry) && dst.kind_of?(Rush::Entry))
			raise ArgumentError, "must operate on Rush::Dir or Rush::File objects"
		end
		
		# 5 cases:
		# 1. local-local
		# 2. local-remote (uploading)
		# 3. remote-local (downloading)
		# 4. remote-remote, same server
		# 5. remote-remote, cross-server
		if src.box == dst.box # case 1 or 4
			if src.box.remote? # case 4
				src.box.ssh.exec!("mv #{src.full_path} #{dst.full_path}") do |ch, stream, data|
					if stream == :stderr
						raise Rush::DoesNotExist, stream
					end
				end
			else # case 1
				FileUtils.mv(src.full_path, dst.full_path)
			end
		else # case 2, 3, or 5
			raise RuntimeError, "Unwise to move a file across the network. Use copy instead"
		end
		new_full_path = dst.dir? ? "#{dst.full_path}#{src.name}" : dst.full_path
		src.class.new(new_full_path, dst.box)
	rescue Errno::ENOENT
		raise Rush::DoesNotExist, File.dirname(to)
	end
	alias :mv :move
	
	##
	# single-box methods should be implemented both in RemoteBox and LocalBox,
	# This is where the documentation goes, though.
	##
	
	##
	# Creates a directory on the box
	# === Parameters
	# [+path+] string representing the (absolute) location of the file to read
	# [+box+] An object inheriting from Rush::Box (ex. Rush::LocalBox)
	# === Returns
	# Rush::Dir object for the newly created directory
	# === Raises
	# * Rush::DoesNotExist if the file doesn't exist
	def mkdir(path, box = nil); 
		@connection.mkdir(path, box)
	end
	
	##
	# Reads data from a file
	# === Behaviors
	# * *remote* - will _only_ read up to 953.67 megabytes, although you probably
	#		don't want to do this anyways.
	# === Parameters
	# [+path+] string representing the (absolute) location of the file to read
	# === Returns
	# the file contents
	# === Raises
	# * Rush::DoesNotExist if the file doesn't exist
	def read(path)
		@connection.read(path)
	end

	##
	# Writes data to a file, overwriting any existing data.
	# === Behaviors
	# * Overwrites existing data
	# === Parameters
	# [+path+] string representing the (absolute) location of the file to write to
	# [+data+] data to write
	# === Returns
	# true on success
	# === Raises
	# * Rush::DoesNotExist if +path+ is invalid
	def write(path, data)
		@connection.write(path, data)
	end
	
	##
	# Checks whether a path points to a directory or a file (via a stat call)
	# === Parameters
	# [+path+] string representing the (absolute) location of the file to check
	# === Returns
	# true if the path points to a directory
	# === Raises
	# * Rush::DoesNotExist if the path is invalid
	def directory?(path)
		@connection.directory?(path)
	end
	
	##
	# Get a list of files from the given path matching the glob. 
	# === Parameters
	# [+path+] string representing the (absolute) location of the dir to
	#		list files in
	# [+glob+] wildcard-based pattern to match files against. Can be a "doubleglob"
	#					 like "**/*.rb", which indicates recursive matching
	# === Returns
	# An array of full paths, directories listed first. If the glob contains a
	# doubleglob, the array will probably contain nested values.
	# === Raises
	# * Rush::DoesNotExist if +path+ is invalid
	def glob(path, glob)
		@connection.glob(path, glob)
	end
		
	##
	# Gets stat info for a file/dir.
	# === Parameters
	# [+path+] string representing the (absolute) location of the file to write to
	# === Returns
	# a hash of stat values. Note that atime, mtime, and ctime are returned as 
	# Time objects. ex:
	# 
	# {
	#		:mode => 16877,
	#		:atime => Fri Sep 05 11:59:23 -0700 2008,
	#		:mtime => Fri Sep 05 11:59:23 -0700 2008,
	#		:ctime => Fri Sep 05 11:59:23 -0700 2008,
	#		:size => 68
	# }
	# 
	# Note that ctime is not available on remote operations and will be
	# returned as nil.
	# === Raises
	# * Rush::DoesNotExist if +path+ is invalid
	def stat(path)
		@connection.stat(path)
	end
	
	##
	# Checks to make sure a file/directory exists
	# === Parameters
	# [+path+] string representing the (absolute) location of the file to write to
	# === Returns
	# true if the file exists, false if not
	# === Raises
	# Nothing
	def exists?(path)
		@connection.exists?(path)
	end
		
	##
	# Updates the atime and mtime of a file, or creates a new file if it doesn't exist.
	# === Parameters
	# [+path+] string representing the (absolute) location of the file to write to
	# === Returns
	# The path to the newly created file (same as was passed in)
	# === Raises
	# * Rush::DoesNotExist if +path+ is invalid
	def touch(path)
		@connection.touch(path)
	end
	
	##### Misc #####

	def to_s				# :nodoc:
		host
	end

	def inspect			# :nodoc:
		host
	end

	##
	# Access stuff on the box. If you pass in a string it will access the filesystem,
	# but a symbol will look up a service.
	# === Parameters
	# [+key+] It is significant whether this is a string or a symbol:
	#					* String: Look up an entry on the filesystem, e.g. 
	#						box['/path/to/some/file'].
	#					* Symbol: Look up a service running on this box, e.g.
	#						box[:mongrel]
	# === Returns
	# Either a subclass of Rush::Entry (see Rush::Entity.factory) or
	# a subclass of Rush::Service (see Rush::Service.factory) depending
	# on whether +key+ is a string or symbol.
	# === Raises
	# nothing
	def [](key)
		if key.is_a?(Symbol)
			Rush::Service.factory(key, self)
		else
			Rush::Entry.factory(key, self)
		end
	end
	

	# Get the list of processes running on the box, not unlike "ps aux" in bash.
	# Returns a Rush::ProcessSet.
	def processes
		Rush::ProcessSet.new(
			connection.processes.map do |ps|
				Rush::Process.new(ps, self)
			end
		)
	end

	# Execute a command in the standard unix shell.	 Returns the contents of
	# stdout if successful, or raises Rush::BashFailed with the output of stderr
	# if the shell returned a non-zero value.	 Options:
	#
	# :user => unix username to become via sudo
	# :env => hash of environment variables
	# :background => run in the background (returns Rush::Process instead of stdout)
	#
	# Examples:
	#
	#		box.bash '/etc/init.d/mysql restart', :user => 'root'
	#		box.bash 'rake db:migrate', :user => 'www', :env => { :RAILS_ENV => 'production' }
	#		box.bash 'mongrel_rails start', :background => true
	#
	def bash(command, options={})
		cmd_with_env = command_with_environment(command, options[:env])

		if options[:background]
			pid = connection.bash(cmd_with_env, options[:user], true)
			processes.find_by_pid(pid)
		else
			connection.bash(cmd_with_env, options[:user], false)
		end
	end

	def command_with_environment(command, env)	# :nodoc:
		return command unless env

		vars = env.map do |key, value|
			"export #{key}='#{value}'"
		end
		vars.push(command).join("\n")
	end

	# Returns true if the box is responding to commands.
	def alive?
		connection.alive?
	end
	
	# This allows us to do things like box.touch('/path/to/file')
	def method_missing(method, *args, &block)
		connection.send(method, *args, &block)
	end
	
	# may wish to call it manually ahead of time in order to have the tunnel
	# already set up and running.	 You can also use this to pass a timeout option,
	# either :timeout => (seconds) or :timeout => :infinite.
	def establish_connection(options={})
		connection.ensure_tunnel(options)
	end

	def ==(other)					 # :nodoc:
		host == other.host
	end
	
	
	private
	
	##
	# Gets the host and user from host and options.
	# === Parameters
	# [+host+] A String representing the host.
	#					 'user@host' syntax can be used to specify the user. If no user
	#					 indicated, it will use the user currently logged in to the OS.
	# [+options+] A hash of options (probably from initialize), of which :user
	#							will be read, set above any other method of getting the user,
	#							and deleted from the options hash
	# === Returns
	# an array of [user, host]
	# === Raises
	# nothing
	def get_host_and_user(host, options = {})
		hostname = host.split("@").last
		if host.split("@").size > 1
			user = host.split("@").first
		else
			# TODO: MS compatability for getting the currently logged in user.
			# The SysUtils gem has a cross-platform method for getting the user
			# but I don't want to add a dependency for everyone just 'cuz MS needs
			# SysUtils. Thus, for MS compatability we would need to check whether
			# we're on windows, then require SysUtils and use it to check for the
			# current user, else use Etc. Some other time...
			user = Etc.getlogin
		end
		user = options.delete(:user) if options[:user]
		return [user, hostname]
	end
end
