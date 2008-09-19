require File.dirname(__FILE__) + '/base'

describe Rush::Box do
	before do
		@sandbox_dir = "/tmp/rush_spec.#{Process.pid}"
		system "rm -rf #{@sandbox_dir}; mkdir -p #{@sandbox_dir}"

		@box = Rush::Box.new('localhost')
	end

	after do
		system "rm -rf #{@sandbox_dir}"
	end

	it "looks up entries with [] syntax" do
		@box['/'].should == Rush::Dir.new('/', @box)
	end

	it "looks up processes" do
		@box.connection.should_receive(:processes).and_return([ { :pid => 123 } ])
		@box.processes.should == [ Rush::Process.new({ :pid => 123 }, @box) ]
	end

	it "executes bash commands" do
		@box.connection.should_receive(:bash).with('cmd', nil, false).and_return('output')
		@box.bash('cmd').should == 'output'
	end

	it "executes bash commands with an optional user" do
		@box.connection.should_receive(:bash).with('cmd', 'user', false)
		@box.bash('cmd', :user => 'user')
	end

	it "executes bash commands in the background, returning a Rush::Process" do
		@box.connection.should_receive(:bash).with('cmd', nil, true).and_return(123)
		@box.stub!(:processes).and_return([ mock('ps', :pid => 123) ])
		@box.bash('cmd', :background => true).pid.should == 123
	end

	it "builds a script of environment variables to prefix the bash command" do
		@box.command_with_environment('cmd', { :a => 'b' }).should == "export a='b'\ncmd"
	end

	it "sets the environment variables from the provided hash" do
		@box.connection.stub!(:bash)
		@box.should_receive(:command_with_environment).with('cmd', { 1 => 2 })
		@box.bash('cmd', :env => { 1 => 2 })
	end

	it "checks the connection to determine if it is alive" do
		@box.connection.should_receive(:alive?).and_return(true)
		@box.should be_alive
	end

	it "establish_connection to set up the connection manually" do
		@box.connection.should_receive(:ensure_tunnel)
		@box.establish_connection
	end

	it "establish_connection can take a hash of options" do
		@box.connection.should_receive(:ensure_tunnel).with(:timeout => :infinite)
		@box.establish_connection(:timeout => :infinite)
	end
	
	before(:each) do
		@src_path = "/path/to/file"
		@dst_path = "/different/to/file"
		@local_box = Rush::Box.new("localhost")
		@remote_box = Rush::Box.new("127.0.0.1")
		@src = mock("src", 
			:box => @local_box,
			:kind_of? => true,
			:full_path => "/path/to/file",
			:class => Rush::File
		)
		@dst = mock("dst",
			:box => @local_box,
			:kind_of? => true,
			:full_path => "/different/to/file",
			:dir? => false
		)
		
	end
	
	describe "[]" do
		it "should look up entries" do
			@local_box['/'].should == Rush::Dir.new('/', @connection)
		end
		
		it "should create services when passed a symbol" do
			@remote_box[:test].class.should == Rush::Service::Test
		end
	end
	
	describe "cp" do
		it "should copy local to local" do
			FileUtils.should_receive(:cp_r).with(@src_path, @dst_path)
			@local_box.cp(@src, @dst)
		end
		
		it "should copy local-remote (uploading)" do
			# remote destination setup
			@dst.stub!(:box).and_return(@remote_box)
			@src.stub!(:local?).and_return(true)
			@dst.stub!(:local?).and_return(false)
			
			# catches the parameters to dst.box.ssh.scp.upload!
			scp = mock("scp")
			scp.should_receive(:upload!).with(@src_path, @dst_path, :recursive => true)
			@remote_box.stub!(:ssh).and_return(mock("ssh", :scp => scp))
			
			@local_box.cp(@src, @dst)
		end
		
		it "should copy remote-local (downloading)" do
			# remote source setup
			@src.stub!(:box).and_return(@remote_box)
			@src.stub!(:local?).and_return(false)
			@dst.stub!(:local?).and_return(true)
			
			# catches the parameters to src.box.ssh.scp.download!
			scp = mock("scp")
			scp.should_receive(:download!).with(@src_path, @dst_path, :recursive => true)
			@remote_box.stub!(:ssh).and_return(mock("ssh", :scp => scp))
			
			@local_box.cp(@src, @dst)
		end

		it "should copy remote-remote, same server" do
			# remote source and destination setup
			@src.stub!(:box).and_return(@remote_box)
			@dst.stub!(:box).and_return(@remote_box)
			
			# catches the parameters to src.box.ssh.exec!
			ssh = mock("ssh")
			ssh.should_receive(:exec!).with("cp -r #{@src_path} #{@dst_path}")
			@remote_box.stub!(:ssh).and_return(ssh)
			
			@local_box.cp(@src, @dst)
		end
		
		it "should copy remote-remote, cross-server" do
			# remote source and destination setup
			@another_remote_box = Rush::Box.new("user@123.456.78.90")
			@src.stub!(:box).and_return(@remote_box)
			@dst.stub!(:box).and_return(@another_remote_box)
			@src.stub!(:local?).and_return(false)
			@dst.stub!(:local?).and_return(false)
			
			# catches the parameters to src.box.ssh.exec!
			ssh = mock("ssh")
			ssh.should_receive(:exec!).with("scp #{@src_path} user@123.456.78.90:#{@dst_path}")
			@remote_box.stub!(:ssh).and_return(ssh)
			
			@local_box.cp(@src, @dst)
		end
	end
	
	describe "mv" do
		it "should move local to local" do
			FileUtils.should_receive(:mv).with(@src_path, @dst_path)
			@local_box.mv(@src, @dst)
		end
		
		it "should move local-remote (uploading)" do
			# remote destination setup
			@dst.stub!(:box).and_return(@remote_box)
			
			lambda{ @local_box.mv(@src, @dst) }.should raise_error(RuntimeError)
		end
		
		it "should move remote-local (downloading)" do
			# remote source setup
			@src.stub!(:box).and_return(@remote_box)
			
			lambda{ @local_box.mv(@src, @dst) }.should raise_error(RuntimeError)
		end

		it "should move remote-remote, same server" do
			# remote source and destination setup
			@src.stub!(:box).and_return(@remote_box)
			@dst.stub!(:box).and_return(@remote_box)
			
			# catches the parameters to src.box.ssh.exec!
			ssh = mock("ssh")
			@remote_box.stub!(:ssh).and_return(ssh)
			
			ssh.should_receive(:exec!).with("mv #{@src_path} #{@dst_path}")
			@local_box.mv(@src, @dst)
		end
		
		it "should move remote-remote, cross-server" do
			# remote source and destination setup
			@another_remote_box = Rush::Box.new("user@123.456.78.90")
			@src.stub!(:box).and_return(@remote_box)
			@dst.stub!(:box).and_return(@another_remote_box)

			lambda{ @local_box.mv(@src, @dst) }.should raise_error(RuntimeError)
		end
	end

	describe 'method_missing' do
		it "should pass undefined calls to the box's connection" do
			box = Rush::Box.new
			connection = mock('connection')
			connection.should_receive(:something).with("parameters")
			box.instance_variable_set(:@connection, connection)
			box.something("parameters")
		end
	end

	describe "get_host_and_user" do
		before(:each) do
			Rush::Box.send(:public, :get_host_and_user)
			@box = Rush::Box.new
		end
		
		it "should parse 'login@somehost' to ['login','somehost']" do
			@box.get_host_and_user("login@somehost").should == ["login", "somehost"]
		end

		it "should parse 'user@somehost', :user => 'someone_else' to ['someone_else','somehost']" do
			@box.get_host_and_user("login@somehost", :user => "someone_else").should == ["someone_else", "somehost"]
		end
		
		it "should parse 'somehost' to ['logged_in_user','somehost']" do
			Etc.should_receive(:getlogin).and_return("logged_in_user")
			@box.get_host_and_user("somehost").should == ['logged_in_user','somehost']
		end
	end
end
