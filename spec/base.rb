require 'rubygems'
require 'spec'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../lib')
require 'rush'

def mock_config(&block)
	mock_config_start
	block.call(config)
	mock_config_end
end

def mock_config_sandbox_dir
	"/tmp/fake_config.#{Process.pid}"
end

def mock_config_start
	mock_config_cleanup
	Rush::Config.new(mock_config_sandbox_dir)
end

def mock_config_cleanup
	FileUtils.rm_rf(mock_config_sandbox_dir)
end

class Rush::Service::Test < Rush::Service; end
class Rush::Service::TestInstance < Rush::ServiceInstance; end
class Rush::Service::TestMe < Rush::Service; end
class Rush::Service::TestMeInstance < Rush::ServiceInstance; end
