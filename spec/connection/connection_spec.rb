describe "a remote or local box", :shared => true	 do
	
	describe "mkdir" do; end
	
	describe "read" do
		it "should read the contents of a file" do
			path = @sandbox_dir + "readme.txt"
			File.open(path, "w") do |file|
				file << "hello"
			end
			@connection.read(path).should == "hello"
			File.delete(path)
		end
		
		it "should raise Rush::DoesNotExist if path is invalid" do
			lambda { @connection.read(@sandbox_dir + "aoeu.txt") }.should raise_error(Rush::DoesNotExist)
		end
	end

	describe "write" do
		it "should write data to a file" do
			path = @sandbox_dir + "readme.txt"
			@connection.write(path, "hello")
			File.open(path, "r") do |file|
				file.read.should == "hello"
			end
			File.delete(path)
		end
		
		it "should raise Rush::DoesNotExist if path is invalid" do
			lambda { @connection.write(@sandbox_dir + "aoeu/aoeu.txt", "hello") }.should raise_error(Rush::DoesNotExist)
		end
	end
	
	describe "touch" do
		it "should create a new empty file if it doesn't exist" do
			file = @sandbox_dir + "touch.txt"
			@connection.touch(file)
			File.exists?(file).should be_true
			FileUtils.rm(file)
		end
		
		it "should update the modification time of an existing file" do
			# # I commented this out 'cuz it requires sleeping for 1 second so
			# # that we can compare mtimes. If we need to test this again, we
			# # can uncomment it, but it's working and I don't see a reason why
			# # it wouldn't work in the future.
			# file = @sandbox_dir + "touch.txt"
			# FileUtils.touch(file)
			# first_mtime = File.mtime(file)
			# sleep(1)
			# @connection.touch(file)
			# second_mtime = File.mtime(file)
			# first_mtime.should < second_mtime
		end
		
		it "should raise Rush::DoesNotExist if path is invalid" do
			lambda { @connection.touch("/aoeu/touch.txt") }.should raise_error(Rush::DoesNotExist)
		end
	end
	
	describe "exists?" do
		it "should return true if the file exists" do
			@connection.exists?("/etc").should be_true
		end
		
		it "should return false if the file does not exist" do
			@connection.exists?("/aoeu").should be_false
		end
	end
	
	describe "directory?" do
		it "checks if a path points to a directory" do
			@connection.directory?("/tmp").should == true
		end
		
		it "should raise Rush::DoesNotExist if path is invalid" do
			lambda { @connection.directory?("/aoeu") }.should raise_error(Rush::DoesNotExist)
		end
	end
	
	describe "entries" do
		before(:each) do
			@dir = @sandbox_dir + "testdir"
			@file = @sandbox_dir + "testfile.txt"
			@hidden_file = @sandbox_dir + ".hidden.txt"
			FileUtils.mkdir(@dir)
			FileUtils.touch(@file)
			FileUtils.touch(@hidden_file)
		end
		
		after(:each) do
			FileUtils.rm_rf(@dir)
		end

		it "should return an array of all files in the directory" do
			@connection.entries(@sandbox_dir).should == ["testdir/", "testfile.txt"]
		end

		it "should accept :a option and return an array that includes hidden directories" do
			@connection.entries(@sandbox_dir, :a).should == [".hidden.txt", "testdir/", "testfile.txt"]
		end
		
		it "should raise Rush::DoesNotExist if path is invalid" do
			lambda { @connection.entries("/aoeu") }.should raise_error(Rush::DoesNotExist)
		end
	end
	
	describe "glob" do
		before(:each) do
			@dir = @sandbox_dir + "testdir"
			@file = @sandbox_dir + "testfile.txt"
			@file_rb = @sandbox_dir + "testfile.rb"
			FileUtils.mkdir(@dir)
			FileUtils.touch(@file)
			FileUtils.touch(@file_rb)
			FileUtils.touch(@dir + "/anothertest.txt")
		end
		
		after(:each) do
			FileUtils.rm_rf(@dir)
		end

		it "should show a list of all files in the directory when no glob is given" do
			@connection.glob(@sandbox_dir).should == ["testdir/", "testfile.rb", "testfile.txt"]
		end

		it "should show a list of files in the directory matching the glob" do
			@connection.glob(@sandbox_dir, "*.rb").should == ["testfile.rb"]
		end

		it "should handle 'double'/recursive globs" do
			@connection.glob(@sandbox_dir, "**/*").should == ["testdir/", "testdir/anothertest.txt", "testfile.rb", "testfile.txt"]
		end
		
		it "should raise Rush::DoesNotExist if path is invalid" do
			lambda { @connection.glob("/aoeu", "*.rb") }.should raise_error(Rush::DoesNotExist)
		end
	end
	
	describe "stat" do
		it "should return a hash of values" do
			# it returns stuff about dates that are hard to match against,
			# so we'll just go with size and a couple class checks.
			box_stat = @connection.stat("/tmp")
			box_stat[:atime].class.should == Time
			box_stat.size.should == 5
		end
		
		it "should raise Rush::DoesNotExist if path is invalid" do
			lambda { @connection.stat("/aoeu") }.should raise_error(Rush::DoesNotExist)
		end
	end
	
	# it "looks up processes" do
	#		@connection.connection.should_receive(:processes).and_return([ { :pid => 123 } ])
	#		@connection.processes.should == [ Rush::Process.new({ :pid => 123 }, @connection) ]
	# end
	# 
	# it "executes bash commands" do
	#		@connection.connection.should_receive(:bash).with('cmd', nil, false).and_return('output')
	#		@connection.bash('cmd').should == 'output'
	# end
	# 
	# it "executes bash commands with an optional user" do
	#		@connection.connection.should_receive(:bash).with('cmd', 'user', false)
	#		@connection.bash('cmd', :user => 'user')
	# end
	# 
	# it "executes bash commands in the background, returning a Rush::Process" do
	#		@connection.connection.should_receive(:bash).with('cmd', nil, true).and_return(123)
	#		@connection.stub!(:processes).and_return([ mock('ps', :pid => 123) ])
	#		@connection.bash('cmd', :background => true).pid.should == 123
	# end
	# 
	# it "builds a script of environment variables to prefix the bash command" do
	#		@connection.command_with_environment('cmd', { :a => 'b' }).should == "export a='b'\ncmd"
	# end
	# 
	# it "sets the environment variables from the provided hash" do
	#		@connection.connection.stub!(:bash)
	#		@connection.should_receive(:command_with_environment).with('cmd', { 1 => 2 })
	#		@connection.bash('cmd', :env => { 1 => 2 })
	# end
end
