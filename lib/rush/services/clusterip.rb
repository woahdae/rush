
class Rush::Service::Clusterip < Rush::Service
  DEFAULTS = {
    :interface => "eth0",
    :virtual_interface => "eth0:0",
    :clustermac => "01:02:03:04:05:06",
    :hashmode => "sourceip"
  }
  
  def instances(*options)
    options = options.to_options_hash
    
    ips = @box["/proc/net/ipt_CLUSTERIP/"].ls
    clusterips = []
    ips.each do |ip|
      clusterip = self.instance(:ip => ip)
      clusterips << clusterip
    end
    
    return clusterips
  end
end

class Rush::Service::ClusteripInstance < Rush::ServiceInstance
  ##
  # Returns the clusterip hash values this node is responsible for as an array
  def responsibility
    res = @box.exec("sudo cat /proc/net/ipt_CLUSTERIP/#{ip}")
    return res ? res.split(",").collect {|i| i.to_i} : []
  end
  
  def responsibility=(*args)
    # the only problem with *args is that if someone puts in an array, we get
    # a two dimensional array. Let's fix this.
    args = args[0] if args[0].kind_of? Array
    
    commands = []
    args.each do |res_for|
      commands << "echo '#{"+" if res_for > 0}#{res_for}' | sudo tee /proc/net/ipt_CLUSTERIP/10.0.3.143 > /dev/null"
    end
    @box.exec(commands.join("; "))
  end
  
  def start(*options)
    options = options.to_options_hash
    
    commands = []
    commands << "sudo iptables -I INPUT -d #{ip} -i #{interface} -j CLUSTERIP --new --clustermac #{clustermac} --hashmode #{hashmode} --total-nodes #{total_nodes} --local-node #{@box.local_node}"
    commands << "sudo ifconfig #{virtual_interface} #{ip}"
    @box.exec(commands.join("; "))
  end
  
  def stop(*options)
    options = options.to_options_hash
    
    commands = []
    commands << "sudo iptables -D INPUT -d #{ip} -i #{interface} -j CLUSTERIP --new --clustermac #{clustermac} --hashmode #{hashmode} --total-nodes #{total_nodes} --local-node #{@box.local_node}"
    commands << "sudo ifconfig #{virtual_interface} down"
    @box.exec(commands.join("; "))
  end
  
  def migrate(dst, *args)
    src_clusterip = self
    dst_clusterip = dst[:clusterip].instance(:ip => ip)

    if args.empty? # migrate everything
      src_responsibility = src_clusterip.responsibility
    else # migrate just the responsibility specified
      src_responsibility = args
    end
    
    dst_clusterip.responsibility = src_responsibility
    src_clusterip.responsibility = src_responsibility.collect {|i| -i}
  end
  
  def status(*options)
    options = options.to_options_hash
    
    commands = []
    status = ""
    running = true
    iptables_status = @box.exec("sudo iptables -L INPUT -n | grep CLUSTERIP")
    if !(iptables_status =~ /^CLUSTERIP.*?#{ip}.*?total_nodes=#{total_nodes}.*?local_node=#{@box.local_node}/)
      running = false
      if options[:v] || options[:verbose]
        status += "not running: iptables\n"
      else
        return "not running"
      end
    end
    
    ip_addy_status = @box.exec("sudo ifconfig | grep #{ip}")
    if !(ip_addy_status =~ /inet addr:#{ip}/)
      running = false
      if options[:v] || options[:verbose]
        status += "not running: interface #{virtual_interface}\n"
      else
        return "not running"
      end
    end
    
    if self.responsibility.size == 0
      running = false
      if options[:v] || options[:verbose]
        status += "not responsible for any nodes\n"
      else
        return "not running"
      end
    end
    
    return running ? "running" : status
  end
  
  def to_s
    "#{ip}: #{status}"
  end
end