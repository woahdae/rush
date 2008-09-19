require 'rubygems'

module Rush; end
module Rush::Connection; end

$LOAD_PATH.unshift(File.dirname(__FILE__))

# need to load these first
require 'rush/commands'
require 'rush/find_by'
require 'rush/head_tail'
require 'rush/entry'
# now include everything in rush and subfolders
Dir.glob(File.join(File.dirname(__FILE__), 'rush/**/*.rb')).each {|f| require f}
