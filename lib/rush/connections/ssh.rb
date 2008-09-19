require 'net/ssh'
require 'net/sftp'
require 'net/scp'

class Rush::Connection::SSH
	attr_accessor :user

	##### Design Notes #####
	# Try to use the Net::SFTP operations if they exist, otherwise use
	# a Net::SSH::Connection::Session#exec! block to execute a bash command
	# and capture stdout/stderr to get values or throw an exception (see touch).
	# I think the latter method is fun and effective, but it seems appropriate
	# to use functionality already made and widely used (ex. Net::SFTP).
	#####
	
	def initialize(box, options = {})
		initialize_options(options)
	end
	
	######### Basic file operations #########
	
	def read(path)
		handle = sftp.open!(path)
		# this will read up to 953.67 megabytes. Probably way more
		# than should be read over sftp anyways.
		# TODO: either check that the file isn't over a certain
		# size, or loop to read files bigger than 953.67 MB (probably the former)
		contents = sftp.read!(handle, 0, 999999999)
		sftp.close!(handle)
		
		return contents || ""
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path
	end
	
	def write(path, contents)
		handle = sftp.open!(path, "w")
		sftp.write!(handle, 0, contents)
		sftp.close!(handle)
		true
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path
	end
	
	def mkdir(path, attrs = {})
		# Net::SSH calls it 'permissions', while FileUtils calls it 'mode'.
		# Let's set apples = oranges
		attrs[:permissions] = attrs[:mode] if attrs[:mode] 
		sftp.mkdir!(path, attrs)
		Rush::Dir.new(path, self)
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path
	end

	def mkdir_p(path)
		ssh.exec!("mkdir -p #{path}")
		Rush::Dir.new(path, self)
	end
	
	def rm(path)
		sftp.remove!(path)
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path
	end
	
	def touch(path)
		# no touch method in Net::SFTP, so let's do it the old fashioned way
		ssh.exec!("touch #{path}") do |ch, stream, data|
			if stream == :stderr
				raise Rush::DoesNotExist, path
			end
		end
		
		return path
	end
	
	######## Directory and file listing/properties stuff #########
	
	def directory?(path)
		sftp.stat!(path).directory?
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path
	end
	
	def exists?(path)
		# there is no exists? in Net::SFTP, but this workaround seems ok.
		# We could use anything that throws an error on a bad path, really.
		self.directory?(path)
		true
	rescue Rush::DoesNotExist
		false
	end
	
	def entries(path, *args)
		results = []
		sftp.dir.foreach(path) do |entry| 
			next if entry.name == "." || entry.name == ".." # skip these
			
			# skip this entry if we're not looking to list hidden directories,
			# and the path starts with "."
			next if !args.include?(:a) && entry.name =~ /^\..*?/

			# append "/" to the end of the name for directories so we can easily see them
			results << (entry.directory? ? entry.name + "/" : entry.name)
		end
		return results.sort
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path	 
	end
	
	def glob(path, glob = nil)
		glob = '*' if glob == '' or glob.nil?
		dirs = []
		files = []
		sftp.dir.glob(path, glob).each do |file|
			if file.directory?
				dirs << file.name + '/'
			else
				files << file.name
			end
		end
		dirs.sort + files.sort
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path
	end
	
	def stat(path)
		stats = sftp.stat!(path)
		ret = {
			:size => stats.size,
			:ctime => nil,
			:atime => Time.at(stats.atime),
			:mtime => Time.at(stats.mtime),
			:mode => stats.permissions,
		}
	rescue Net::SFTP::StatusException
		raise Rush::DoesNotExist, path
	end
	
	##### Misc #####
	
	##
	# Executes a command. Seems simple enough, but supporting sudo makes it 
	# difficult.
	def exec(cmd)
		# the built in ssh.exec wraps some stuff up for us, but to catch sudo we 
		# have to construct the whole thing ourselves, starting with the channel.
		channel = ssh.open_channel do |channel|
			# now we request a "pty" (i.e. interactive) session so we can send data
			# back and forth if needed. it WILL NOT WORK without this, and it has to
			# be done before any call to exec.
			channel.request_pty do |ch, success|
				raise "Could not obtain pty (i.e. an interactive ssh session)" if !success
			end

			channel.exec(cmd) do |ch, success|
				# 'success' isn't related to bash exit codes or anything, but more
				# about ssh internals (i think... not bash related anyways).
				# not sure why it would fail at such a basic level, but it seems smart
				# to do something about it.
				abort "could not execute command" unless success
				
				# on_data is a hook that fires when the loop that this block is fired
				# in (see below) returns data. This is what we've been doing all this
				# for; now we can check to see if it's a password prompt, and 
				# interactively return data if so (see request_pty above).
				channel.on_data do |ch, data|
					if data == "Password:"
						raise "The connection asked for a sudo password, and I don't have one" unless @password
						channel.send_data "#{@password}\n"
					else
						# ssh channels can be treated as a hash for the specific purpose of
						# getting values out of the block later
						channel[:result] ||= ""
						channel[:result] << data
					end 
				end
				
				channel.on_extended_data do |ch, type, data|
					raise "SSH command returned on stderr: #{data}"
				end
			end
		end

		# Nothing has actually happened yet. Everything above will respond to the
		# server after each execution of the ssh loop until it has nothing left
		# to process. For example, if the above recieved a password challenge from
		# the server, ssh's exec loop would execute twice - once for the password,
		# then again after clearing the password (or twice more and exit if the
		# password was bad)
		channel.wait
		
		# it returns with \r\n at the end
		return channel[:result] ? channel[:result].strip : nil
	end
	
	# returns the ssh connection opened for the box, or starts a new one if none
	# existed
	def ssh
		@ssh ||= Net::SSH.start(
			@host,
			@user,
			:password => @password,
			:port => (@port || 22)
		)
	end
	
	# returns a Net::SFTP instance based on the current Net::SSH connection
	def sftp
		ssh.sftp
	end
	
	# No-op for duck typing with rushd connection.
	def ensure_tunnel(options={})
	end
	
	def remote?
		true
	end

	alias :write_file    :write   
	alias :file_contents :read    
	alias :destroy       :rm      
	alias :create_dir    :mkdir_p 
	alias :index         :glob    
	alias :bash          :exec    
end