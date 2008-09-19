require File.dirname(__FILE__) + '/../base'
require File.dirname(__FILE__) + '/connection_spec'

describe Rush::Connection::SSH do
	before do
		@sandbox_dir = "/tmp/rush_spec.#{Process.pid}/"
		system "rm -rf #{@sandbox_dir}; mkdir -p #{@sandbox_dir}"
		@box = mock("box")
		
		@connection = Rush::Connection::SSH.new(@box, :user => 'woody',:host => '127.0.0.1', :password => nil)
	end

	after do
		system "rm -rf #{@sandbox_dir}"
	end

	describe "exec" do
		it "should execute a remote command and return the results" do
			@connection.exec("echo 'hello'").should == 'hello'
		end
		
		# # commented because it will complain that you haven't set a sudo password.
		# # you could set password => 'pass' above and uncomment to check that it works,
		# # but I don't want to require that users put their password somewhere just for
		# # testing.
		# it "should execute a remote command with sudo and return the results" do
		# 	@connection.exec("sudo echo 'hello'").should == 'hello'
		# end
		
		it "should raise a RuntimeError when sudo asks for a password, but the connection doesn't have one set" do
			password = @connection.instance_variable_get(:@password)
			@connection.instance_variable_set(:@password, nil)
			lambda { @connection.exec("sudo echo 'hello'") }.should raise_error(RuntimeError)
			@connection.instance_variable_set(:@password, password)
		end
	end
	
	it_should_behave_like "a remote or local box"
end