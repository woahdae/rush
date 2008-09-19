require File.dirname(__FILE__) + '/../base'
require File.dirname(__FILE__) + '/connection_spec'
describe Rush::Connection::Local do
	before do
		@sandbox_dir = "/tmp/rush_spec.#{Process.pid}/"
		system "rm -rf #{@sandbox_dir}; mkdir -p #{@sandbox_dir}"

		@con = Rush::Connection::Local.new
		@connection = @con
	end

	it_should_behave_like "a remote or local box"

	after do
		system "rm -rf #{@sandbox_dir}"
	end

	it "write_file writes contents to a file" do
		fname = "#{@sandbox_dir}/a_file"
		data = "some data"
		@con.write_file(fname, data)
		File.read(fname).should == data
	end

	it "file_contents reads a file's contents" do
		fname = "#{@sandbox_dir}/a_file"
		system "echo stuff > #{fname}"
		@con.file_contents(fname).should == "stuff\n"
	end

	it "file_contents raises DoesNotExist if the file does not exist" do
		fname = "#{@sandbox_dir}/does_not_exist"
		lambda { @con.file_contents(fname) }.should raise_error(Rush::DoesNotExist, fname)
	end

	it "destroy to destroy a file or dir" do
		fname = "#{@sandbox_dir}/delete_me"
		system "touch #{fname}"
		@con.destroy(fname)
		File.exists?(fname).should be_false
	end

	it "purge to purge a dir" do
		system "cd #{@sandbox_dir}; touch {1,2}; mkdir 3; touch 3/4"
		@con.purge(@sandbox_dir)
		File.exists?(@sandbox_dir).should be_true
		Dir.glob("#{@sandbox_dir}/*").should == []
	end

	it "purge kills hidden (dotfile) entries too" do
		system "cd #{@sandbox_dir}; touch .killme"
		@con.purge(@sandbox_dir)
		File.exists?(@sandbox_dir).should be_true
		`cd #{@sandbox_dir}; ls -lA | grep -v total | wc -l`.to_i.should == 0
	end

	it "create_dir creates a directory" do
		fname = "#{@sandbox_dir}/a/b/c/"
		@con.create_dir(fname)
		File.directory?(fname).should be_true
	end

	it "rename to rename entries within a dir" do
		system "touch #{@sandbox_dir}/a"
		@con.rename(@sandbox_dir, 'a', 'b')
		File.exists?("#{@sandbox_dir}/a").should be_false
		File.exists?("#{@sandbox_dir}/b").should be_true
	end

	it "copy to copy an entry to another dir on the same box" do
		system "mkdir #{@sandbox_dir}/subdir"
		system "touch #{@sandbox_dir}/a"
		@con.copy("#{@sandbox_dir}/a", "#{@sandbox_dir}/subdir")
		File.exists?("#{@sandbox_dir}/a").should be_true
		File.exists?("#{@sandbox_dir}/subdir/a").should be_true
	end

	it "copy raises DoesNotExist with source path if it doesn't exist or otherwise can't be accessed" do
		lambda { @con.copy('/does/not/exist', '/tmp') }.should raise_error(Rush::DoesNotExist, '/does/not/exist')
	end

	it "copy raises DoesNotExist with destination path if it can't access the destination" do
		lambda { @con.copy('/tmp', '/does/not/exist') }.should raise_error(Rush::DoesNotExist, '/does/not')
	end

	it "read_archive to pull an archive of a dir into a byte stream" do
		system "touch #{@sandbox_dir}/a"
		@con.read_archive(@sandbox_dir).size.should > 50
	end

	it "write_archive to turn a byte stream into a dir" do
		system "cd #{@sandbox_dir}; mkdir -p a; touch a/b; tar cf xfer.tar a; mkdir dst"
		archive = File.read("#{@sandbox_dir}/xfer.tar")
		@con.write_archive(archive, "#{@sandbox_dir}/dst")
		File.directory?("#{@sandbox_dir}/dst/a").should be_true
		File.exists?("#{@sandbox_dir}/dst/a/b").should be_true
	end

	it "index fetches list of all files and dirs in a dir when pattern is empty" do
		system "cd #{@sandbox_dir}; mkdir dir; touch file"
		@con.index(@sandbox_dir, '').should == [ 'dir/', 'file' ]
	end

	it "index fetches only files with a certain extension with a flat pattern, *.rb" do
		system "cd #{@sandbox_dir}; touch a.rb; touch b.txt"
		@con.index(@sandbox_dir, '*.rb').should == [ 'a.rb' ]
	end

	it "index raises DoesNotExist when the base path is invalid" do
		lambda { @con.index('/does/not/exist', '*') }.should raise_error(Rush::DoesNotExist, '/does/not/exist')
	end

	it "stat gives file stats like size and timestamps" do
		@con.stat(@sandbox_dir).should have_key(:ctime)
		@con.stat(@sandbox_dir).should have_key(:size)
	end

	it "stat fetches the octal permissions" do
		@con.stat(@sandbox_dir)[:mode].should be_kind_of(Fixnum)
	end

	it "stat raises DoesNotExist if the entry does not exist" do
		fname = "#{@sandbox_dir}/does_not_exist"
		lambda { @con.stat(fname) }.should raise_error(Rush::DoesNotExist, fname)
	end

	it "set_access invokes the access object" do
		access = mock("access")
		access.should_receive(:apply).with('/some/path')
		@con.set_access('/some/path', access)
	end

	if !RUBY_PLATFORM.match(/darwin/)   # doesn't work on OS X 'cause du switches are different
		it "size gives size of a directory and all its contents recursively" do
			system "mkdir -p #{@sandbox_dir}/a/b/; echo 1234 > #{@sandbox_dir}/a/b/c"
			@con.size(@sandbox_dir).should == (4096*3 + 5)
		end
	end

	it "parses ps output on os x" do
		@con.parse_ps("21712   501   21711   1236   0 /usr/bin/vi somefile.rb").should == {
			:pid => "21712",
			:uid => "501",
			:parent_pid => 21711,
			:mem => 1236,
			:cpu => 0,
			:command => '/usr/bin/vi',
			:cmdline => '/usr/bin/vi somefile.rb',
		}
	end

	it "gets the list of processes on os x via the ps command" do
		@con.should_receive(:os_x_raw_ps).and_return <<EOPS
PID UID   PPID  RSS  CPU COMMAND
1     0      1 1111   0 cmd1 args
2   501      1  222   1 cmd2
EOPS
		@con.os_x_processes.should == [
			{ :pid => "1", :uid => "0", :parent_pid => 1, :mem => 1111, :cpu => 0, :command => "cmd1", :cmdline => "cmd1 args" },
			{ :pid => "2", :uid => "501", :parent_pid => 1, :mem => 222, :cpu => 1, :command => "cmd2", :cmdline => "cmd2" },
		]
	end

	it "the current process should be alive" do
		@con.process_alive(Process.pid).should be_true
	end

	it "a made-up process should not be alive" do
		@con.process_alive(99999).should be_false
	end

	it "kills a process by pid" do
		::Process.should_receive(:kill).at_least(:once)
		@con.kill_process(123)
	end

	it "does not raise an error if the process is already dead" do
		::Process.should_receive(:kill).and_raise(Errno::ESRCH)
		lambda { @con.kill_process(123) }.should_not raise_error
	end

	it "executes a bash command, returning stdout when successful" do
		@con.bash("echo test").should == "test\n"
	end

	it "executes a bash command, raising and error (with stderr as the message) when return value is nonzero" do
		lambda { @con.bash("no_such_bin") }.should raise_error(Rush::BashFailed, /command not found/)
	end

	it "executes a bash command as another user using sudo" do
		@con.bash("echo test2", ENV['USER']).should == "test2\n"
	end

	it "executes a bash command in the background, returning the pid" do
		@con.bash("true", nil, true).should > 0
	end

	it "ensure_tunnel to match with remote connection" do
		@con.ensure_tunnel
	end

	it "always returns true on alive?" do
		@con.should be_alive
	end

	it "resolves a unix uid to a user" do
		@con.resolve_unix_uid_to_user(0).should == "root"
		@con.resolve_unix_uid_to_user('0').should == "root"
	end

	it "returns nil if the unix uid does not exist" do
		@con.resolve_unix_uid_to_user(9999).should be_nil
	end

	it "iterates through a process list and resolves the unix uid for each" do
		list = [ { :uid => 0, :command => 'pureftpd' }, { :uid => 9999, :command => 'defunk' } ]
		@con.resolve_unix_uids(list).should == [ { :uid => 0, :user => 'root', :command => 'pureftpd' }, { :uid => 9999, :command => 'defunk', :user => nil } ]
	end

	it "method_missing should pass undefined calls to the box's connection" do
		box = Rush::Box.new
		connection = mock('connection')
		connection.should_receive(:something).with("parameters")
		box.instance_variable_set(:@connection, connection)
		box.something("parameters")
	end

end
