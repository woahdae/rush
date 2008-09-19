require File.dirname(__FILE__) + '/../base'

describe Rush::Connection::Rushd do
	before do
		@con = Rush::Connection::Rushd.new('spec.example.com')
	end

	it "transmits write_file" do
		@con.should_receive(:transmit).with(:action => 'write_file', :full_path => 'file', :payload => 'contents')
		@con.write_file('file', 'contents')
	end

	it "transmits file_contents" do
		@con.should_receive(:transmit).with(:action => 'file_contents', :full_path => 'file').and_return('contents')
		@con.file_contents('file').should == 'contents'
	end

	it "transmits destroy" do
		@con.should_receive(:transmit).with(:action => 'destroy', :full_path => 'file')
		@con.destroy('file')
	end

	it "transmits purge" do
		@con.should_receive(:transmit).with(:action => 'purge', :full_path => 'dir')
		@con.purge('dir')
	end

	it "transmits create_dir" do
		@con.should_receive(:transmit).with(:action => 'create_dir', :full_path => 'file')
		@con.create_dir('file')
	end

	it "transmits rename" do
		@con.should_receive(:transmit).with(:action => 'rename', :path => 'path', :name => 'name', :new_name => 'new_name')
		@con.rename('path', 'name', 'new_name')
	end

	it "transmits copy" do
		@con.should_receive(:transmit).with(:action => 'copy', :src => 'src', :dst => 'dst')
		@con.copy('src', 'dst')
	end

	it "transmits touch" do
		@con.should_receive(:transmit).with(:action => 'touch', :full_path => 'path')
		@con.touch('path')
	end

	it "transmits read_archive" do
		@con.should_receive(:transmit).with(:action => 'read_archive', :full_path => 'full_path').and_return('archive data')
		@con.read_archive('full_path').should == 'archive data'
	end

	it "transmits write_archive" do
		@con.should_receive(:transmit).with(:action => 'write_archive', :dir => 'dir', :payload => 'archive')
		@con.write_archive('archive', 'dir')
	end

	it "transmits index" do
		@con.should_receive(:transmit).with(:action => 'index', :base_path => 'base_path', :glob => '*').and_return("1\n2\n")
		@con.index('base_path', '*').should == %w(1 2)
	end

	it "transmits stat" do
		@con.should_receive(:transmit).with(:action => 'stat', :full_path => 'full_path').and_return(YAML.dump(1 => 2))
		@con.stat('full_path').should == { 1 => 2 }
	end

	it "transmits set_access" do
		@con.should_receive(:transmit).with(:action => 'set_access', :full_path => 'full_path', :user => 'joe', :user_read => 1)
		@con.set_access('full_path', :user => 'joe', :user_read => 1)
	end

	it "transmits size" do
		@con.should_receive(:transmit).with(:action => 'size', :full_path => 'full_path').and_return("123")
		@con.size('full_path').should == 123
	end

	it "transmits processes" do
		@con.should_receive(:transmit).with(:action => 'processes').and_return(YAML.dump([ { :pid => 1 } ]))
		@con.processes.should == [ { :pid => 1 } ]
	end

	it "transmits process_alive" do
		@con.should_receive(:transmit).with(:action => 'process_alive', :pid => 123).and_return(true)
		@con.process_alive(123).should == true
	end

	it "transmits kill_process" do
		@con.should_receive(:transmit).with(:action => 'kill_process', :pid => 123)
		@con.kill_process(123)
	end

	it "transmits bash" do
		@con.should_receive(:transmit).with(:action => 'bash', :payload => 'cmd', :user => 'user', :background => 'bg').and_return('output')
		@con.bash('cmd', 'user', 'bg').should == 'output'
	end

	it "an http result code of 401 raises NotAuthorized" do
		lambda { @con.process_result("401", "") }.should raise_error(Rush::NotAuthorized)
	end

	it "an http result code of 400 raises the exception passed in the result body" do
		@con.stub!(:parse_exception).and_return(Rush::DoesNotExist, "message")
		lambda { @con.process_result("400", "") }.should raise_error(Rush::DoesNotExist)
	end

	it "an http result code of 501 (or anything other than the other defined codes) raises FailedTransmit" do
		lambda { @con.process_result("501", "") }.should raise_error(Rush::FailedTransmit)
	end

	it "parse_exception takes the class from the first line and the message from the second" do
		@con.parse_exception("Rush::DoesNotExist\nthe message\n").should == [ Rush::DoesNotExist, "the message" ]
	end

	it "parse_exception rejects unrecognized exceptions" do
		lambda { @con.parse_exception("NotARushException\n") }.should raise_error
	end

	it "passes through ensure_tunnel" do
		@con.tunnel.should_receive(:ensure_tunnel)
		@con.ensure_tunnel
	end

	it "is alive if the box is responding to commands" do
		@con.should_receive(:index).and_return(:dummy)
		@con.should be_alive
	end

	it "not alive if an attempted command throws an exception" do
		@con.should_receive(:index).and_raise(RuntimeError)
		@con.should_not be_alive
	end
end

describe Rush::Connection::Local do
	before do
		@con = Rush::Connection::Local.new
	end
	
	it "receive -> write_file(file, contents)" do
		@con.should_receive(:write_file).with('file', 'contents')
		@con.receive(:action => 'write_file', :full_path => 'file', :payload => 'contents')
	end

	it "receive -> file_contents(file)" do
		@con.should_receive(:file_contents).with('file').and_return('the contents')
		@con.receive(:action => 'file_contents', :full_path => 'file').should == 'the contents'
	end

	it "receive -> destroy(file or dir)" do
		@con.should_receive(:destroy).with('file')
		@con.receive(:action => 'destroy', :full_path => 'file')
	end

	it "receive -> purge(dir)" do
		@con.should_receive(:purge).with('dir')
		@con.receive(:action => 'purge', :full_path => 'dir')
	end

	it "receive -> create_dir(path)" do
		@con.should_receive(:create_dir).with('dir')
		@con.receive(:action => 'create_dir', :full_path => 'dir')
	end

	it "receive -> rename(path, name, new_name)" do
		@con.should_receive(:rename).with('path', 'name', 'new_name')
		@con.receive(:action => 'rename', :path => 'path', :name => 'name', :new_name => 'new_name')
	end

	it "receive -> copy(src, dst)" do
		@con.should_receive(:copy).with('src', 'dst')
		@con.receive(:action => 'copy', :src => 'src', :dst => 'dst')
	end

	it "receive -> read_archive(full_path)" do
		@con.should_receive(:read_archive).with('full_path').and_return('archive data')
		@con.receive(:action => 'read_archive', :full_path => 'full_path').should == 'archive data'
	end

	it "receive -> write_archive(archive, dir)" do
		@con.should_receive(:write_archive).with('archive', 'dir')
		@con.receive(:action => 'write_archive', :dir => 'dir', :payload => 'archive')
	end

	it "receive -> index(base_path, glob)" do
		@con.should_receive(:index).with('base_path', '*').and_return(%w(1 2))
		@con.receive(:action => 'index', :base_path => 'base_path', :glob => '*').should == "1\n2\n"
	end

	it "receive -> stat(full_path)" do
		@con.should_receive(:stat).with('full_path').and_return(1 => 2)
		@con.receive(:action => 'stat', :full_path => 'full_path').should == YAML.dump(1 => 2)
	end

	it "receive -> set_access(full_path, user, group, permissions)" do
		access = mock("access")
		Rush::Access.should_receive(:from_hash).with(:action => 'set_access', :full_path => 'full_path', :user => 'joe').and_return(access)

		@con.should_receive(:set_access).with('full_path', access)
		@con.receive(:action => 'set_access', :full_path => 'full_path', :user => 'joe')
	end

	it "receive -> size(full_path)" do
		@con.should_receive(:size).with('full_path').and_return("1024")
		@con.receive(:action => 'size', :full_path => 'full_path').should == "1024"
	end

	it "receive -> processes" do
		@con.should_receive(:processes).with().and_return([ { :pid => 1 } ])
		@con.receive(:action => 'processes').should == YAML.dump([ { :pid => 1 } ])
	end

	it "receive -> process_alive" do
		@con.should_receive(:process_alive).with(123).and_return(true)
		@con.receive(:action => 'process_alive', :pid => 123).should == '1'
	end

	it "receive -> kill_process" do
		@con.should_receive(:kill_process).with(123).and_return(true)
		@con.receive(:action => 'kill_process', :pid => '123')
	end

	it "receive -> bash (foreground)" do
		@con.should_receive(:bash).with('cmd', 'user', false).and_return('output')
		@con.receive(:action => 'bash', :payload => 'cmd', :user => 'user', :background => 'false').should == 'output'
	end

	it "receive -> bash (background)" do
		@con.should_receive(:bash).with('cmd', 'user', true).and_return('output')
		@con.receive(:action => 'bash', :payload => 'cmd', :user => 'user', :background => 'true').should == 'output'
	end

	it "receive -> unknown action exception" do
		lambda { @con.receive(:action => 'does_not_exist') }.should raise_error(Rush::Connection::Local::UnknownAction)
	end
end