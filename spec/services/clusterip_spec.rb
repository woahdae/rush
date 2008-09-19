require File.dirname(__FILE__) + '/../base'

describe Rush::Service::Clusterip do
  describe "instances" do
    it "should return an array of ClusteripInstance objects" do
      @box = mock(Rush::Box)
      @clusterip_service = Rush::Service::Clusterip.new(@box)
      
      # cut it off from actually looking up ip addresses
      @clusterip_dir = mock(Rush::Dir, :ls => ["123.456.78.90","123.456.78.91"])
      @box.stub!(:[]).with("/proc/net/ipt_CLUSTERIP/").and_return(@clusterip_dir)
      
      # do some checks
      ips = @clusterip_service.instances
      ips.first.class.should == Rush::Service::ClusteripInstance
      ips.size.should == 2
    end
  end
end

describe Rush::Service::ClusteripInstance do
  before(:each) do
    @box = mock(Rush::Box, :local_node => 1)
    @cip_instance = Rush::Service::ClusteripInstance.new(@box, 
      :ip => "123.456.78.90",
      :total_nodes => 3
    )
  end

  describe "responsibility" do
    it "should return an array of stringified numbers representing which
        fraction of all total nodes this node is responsible for" do
      @box.should_receive(:exec).
        with('sudo cat /proc/net/ipt_CLUSTERIP/123.456.78.90').
        and_return("1,2")
      @cip_instance.responsibility.should == [1,2]
    end
  end
  
  describe "responsibility=" do
    it "should add the clusterip responsibility to the specified ip" do
      @box.should_receive(:exec).
        with("echo '+1' | sudo tee /proc/net/ipt_CLUSTERIP/10.0.3.143 > /dev/null; echo '-2' | sudo tee /proc/net/ipt_CLUSTERIP/10.0.3.143 > /dev/null")
      @cip_instance.responsibility = 1,-2
    end
    
    it "should work even when passed an array" do
      @box.should_receive(:exec).
        with("echo '+1' | sudo tee /proc/net/ipt_CLUSTERIP/10.0.3.143 > /dev/null; echo '-2' | sudo tee /proc/net/ipt_CLUSTERIP/10.0.3.143 > /dev/null")
      @cip_instance.responsibility = [1,-2]
    end
  end
  
  describe "start" do
    it "should start the clusterip service on the box" do
      @box.should_receive(:exec).with("sudo iptables -I INPUT -d 123.456.78.90 -i eth0 -j CLUSTERIP --new --clustermac 01:02:03:04:05:06 --hashmode sourceip --total-nodes 3 --local-node 1; sudo ifconfig eth0:0 123.456.78.90")
      @cip_instance.start
    end
  end
  
  describe "stop" do
    it "should stop the clusterip service on the box" do
      @box.should_receive(:exec).with("sudo iptables -D INPUT -d 123.456.78.90 -i eth0 -j CLUSTERIP --new --clustermac 01:02:03:04:05:06 --hashmode sourceip --total-nodes 3 --local-node 1; sudo ifconfig eth0:0 down")
      @cip_instance.stop
    end
  end
  
  describe "status" do
    before(:each) do
      @box.stub!(:exec).
        with("sudo iptables -L INPUT -n | grep CLUSTERIP").
        and_return("CLUSTERIP  0    --  0.0.0.0/0            123.456.78.90          CLUSTERIP hashmode=sourceip clustermac=01:02:03:04:05:06 total_nodes=3 local_node=1 hash_init=0")
      
      @box.stub!(:exec).
        with("sudo ifconfig | grep 123.456.78.90").
        and_return("inet addr:123.456.78.90  Bcast:10.255.255.255  Mask:255.0.0.0")
        
      @cip_instance.stub!(:responsibility).and_return([1])
    end
    it "should return 'running' when all things match up correctly" do
      @cip_instance.status.should == "running"
    end
    
    it "should return 'not running' when iptables is down" do
      @box.stub!(:exec).
        with("sudo iptables -L INPUT -n | grep CLUSTERIP").
        and_return(nil)
        
      @cip_instance.status.should == "not running"
    end

    it "should return 'not running' when interface is down" do
      @box.stub!(:exec).
        with("sudo ifconfig | grep 123.456.78.90").
        and_return(nil)
        
      @cip_instance.status.should == "not running"
    end
    
    it "should return 'not running' when not responsible for anything" do
      @cip_instance.stub!(:responsibility).and_return([])
      
      @cip_instance.status.should == "not running"
    end
    
    it "should return verbose output with the :v flag on failure" do
      @box.stub!(:exec).
        with("sudo iptables -L INPUT -n | grep CLUSTERIP").
        and_return(nil)
      
      @box.stub!(:exec).
        with("sudo ifconfig | grep 123.456.78.90").
        and_return(nil)
        
      @cip_instance.stub!(:responsibility).and_return([])
      
      @cip_instance.status(:v).should == "not running: iptables\nnot running: interface eth0:0\nnot responsible for any nodes\n"
    end
  end
  
  describe "migrate" do
    before(:each) do
      @dst_cip_instance = mock(Rush::Service::ClusteripInstance)
      @dst_cip_service = mock(Rush::Service::Clusterip, :instance => @dst_cip_instance)
      @dst = mock(Rush::Box, :[] => @dst_cip_service)
      @cip_instance.stub!(:responsibility).and_return([1,2])
    end
    
    it "should subtract src's node responsibility, and add it to dst's responsibility" do
      @cip_instance.should_receive(:responsibility=).with([-1,-2])
      @dst_cip_instance.should_receive(:responsibility=).with([1,2])
      @cip_instance.migrate(@dst)
    end
    
    it "should subtract specified responsibility from src node, and add it to dst_node" do
      @cip_instance.should_receive(:responsibility=).with([-1])
      @dst_cip_instance.should_receive(:responsibility=).with([1])
      @cip_instance.migrate(@dst, 1)
    end
  end
end






