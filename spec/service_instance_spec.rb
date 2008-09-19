require File.dirname(__FILE__) + '/base'

describe Rush::ServiceInstance do
  
  describe "new" do
    it "should properly initialize the service name" do
      @service_instance = Rush::Service::TestInstance.new(mock(Rush::Box))
      @service_instance.service_name.should == "Test"
    end
    
    it "should raise a RuntimeError if called from Rush::ServiceInstance" do
      lambda {Rush::ServiceInstance.new(mock(Rush::Box))}.should raise_error(RuntimeError)
    end
  end

  describe "self.factory" do
    it "should call 'new' on a class constructed from the symbol" do
      Rush::Service::TestInstance.should_receive(:new)
      Rush::ServiceInstance.factory(:test, mock(Rush::Box))
    end

    it "should call 'new' on a class constructed from the symbol,
        even when the symbol should result in a more complicated camelcase" do
      Rush::Service::TestMeInstance.should_receive(:new)
      Rush::ServiceInstance.factory(:test_me, mock(Rush::Box))
    end
  end
  
  describe "migrate" do
    before(:each) do
      @box1 = mock(Rush::Box)
      @box2 = mock(Rush::Box)
      @box1_service = mock(Rush::Service, :name => :test, :box => @box1)
      @box2_service = mock(Rush::Service, :name => :test, :box => @box2)
      @box1.stub!(:service).and_return(@box1_service)
      @box2.stub!(:service).and_return(@box2_service)
      @box1_service_instance = Rush::Service::TestInstance.new(@box1, :port => 3000)
      @box2_service_instance = Rush::Service::TestInstance.new(@box2, :port => 3000)

      @box2.stub!(:[]).with(:test).and_return(@box2_service)
      @box1_service_instance.stub!(:stop)
      @box2_service_instance.stub!(:start)
      Rush::Service::TestInstance.stub!(:new).and_return(@box2_service_instance)
    end
    
    it "should stop the instance on this box, and start it on another" do
      @box1_service_instance.should_receive(:stop)
      @box2_service_instance.should_receive(:start)
      @box1_service_instance.migrate(@box2)
    end
    
    it "should return a Rush::ServiceInstance object for the new instance" do
      @box1_service_instance.migrate(@box2).should == @box2_service_instance
    end
  end

end 
