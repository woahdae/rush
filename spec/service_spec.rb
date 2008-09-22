require File.dirname(__FILE__) + '/base'

describe Rush::Service do
  describe "new" do
    it "should properly instantiate its name" do
      @service = Rush::Service::Test.new(mock(Rush::Box))
      @service.name.should == "Test"
    end
    
    it "should raise a RuntimeError if called from Rush::ServiceInstance" do
      lambda {Rush::ServiceInstance.new(mock(Rush::Box))}.should raise_error(RuntimeError)
    end
    
  end

  describe "self.service_name" do
    it "should correctly parse the name of the service from the class name" do
      Rush::Service::Test.service_name.should == "Test"
    end
  end

  describe "factory" do
    it "should call 'new' on a class constructed from the symbol" do
      Rush::Service::Test.should_receive(:new)
      Rush::Service.factory(:test, mock(Rush::Box))
    end
  end
  
  describe "to_s" do
    it "should call status" do
      @service = Rush::Service::Test.new(mock("box"))
      @service.should_receive(:status)
      @service.to_s
    end
  end
  
  describe "status" do
  end
  
  describe "migrate" do
    it "should move all instances of a service to another box" do
      @box1 = mock(Rush::Box)
      @box2 = mock(Rush::Box)
      service = Rush::Service.factory(:test, @box1)

      @instance1 = mock(Rush::Service::TestInstance)
      @instance2 = mock(Rush::Service::TestInstance)
      service.stub!(:instances).and_return([@instance1, @instance2])

      @instance1.should_receive(:migrate).with(@box2)
      @instance2.should_receive(:migrate).with(@box2)
      
      service.migrate(@box2)
    end
  end
  
  describe "instance" do
    it "should pass on *options correctly" do
      @box = mock(Rush::Box)
      @service = Rush::Service::Test.new(@box, :flag)
      Rush::Service::TestInstance.should_receive(:new).with(@box, {:flag => true, :another_flag => true, :ip => "123.456.78.90"})
      @service.instance(:another_flag, :ip => "123.456.78.90")
    end
  end
  
  describe "self.final_options" do
    it "should correctly merge defaults, config options, and parameter options, taking priority into account" do
      @service = Rush::Service::Test.new(mock(Rush::Box))
      Rush::Service::Test::DEFAULTS = {:hello => "hello", :not => false, :two_n_two => "5" }
      Rush::Config.should_receive("load_yaml").with(:section => :test).and_return({:not => true, :two_n_two => "6"})
      results = Rush::Service::Test.final_options(:two_n_two => "4")
      results.should == {:hello => "hello", :not => true, :two_n_two => "4"}
    end
  end
end

