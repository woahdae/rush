
##
# === Creating New Services
# See Rush::Service documentation
class Rush::ServiceInstance 
  attr_accessor :service_name, :box, :options
  
  ##
  # For creating new Rush::ServiceInstance *subclass* instances.
  # 
  # You can call new on a subclass to create Service instances
  # (e.g. Rush::Service::MongrelInstance.new(box)), or use
  # Rush::ServiceInstance.factory. One is almost always cleaner than the other.
  # === Behaviors
  # * Stores all +*option+ values in their own instance variable
  # * stores the box, service_name, and options in instance variables
  # === Parameters
  # [+box+]      A Rush::Box subclass instance, ex. Rush::RemoteBox
  # [+*options+] Options needed to initialize the particular ServiceInstance.
  #              Ex, a mongrel service instance would need to know what port
  #              to run on (among other things), while an ip address would
  #              need to know what its ip address is. These will be
  #              stored as a hash in the @options instance variable for later
  #              reference in methods such as start, stop, status, etc.
  # 
  #              It is interesting to note that +*options+ can take unix-like
  #              flags that will automatically be set to true in the options hash.
  #              For example, ServiceInstance.new(box, :debug_mode, :port => 3000)
  #              would produce an options hash of 
  #              {:debug_mode => true, :port => 3000}. Caveat: flags MUST come
  #              before key-value options. See +to_options_hash+ for more info.
  # === Returns
  # Nothing in particular
  # === Raises
  # * RuntimeError if new is called from Rush::ServiceInstance
  def initialize(box, *options)
    if self.class == Rush::ServiceInstance
      raise "Cannot call new from Rush::ServiceInstance - use factory instead"
    end
    
    @box = box
    @service_name = self.class.service_name
    
    service_class = Kernel.qualified_const_get("Rush::Service::#{@service_name}")
    initialize_options(service_class.final_options(*options))
  end
  
  ##
  # Convenience method that creates a new Rush::ServiceInstance subclass
  # instance based on the +service_name+ parameter, aka
  # "Rush::Service::[ServiceName]Instance"
  # 
  # Ex. Rush::ServiceInstance.factory(:mongrel, box, :port => 3000) would
  # call Rush::Service::MongrelInstance.new(box, :port => 3000)
  # 
  # Note: although .new and .factory do the same thing, one is almost always
  # cleaner than the other in a given context.
  # === Parameters
  # [+service_name+] A service name, ex. +Mongrel+. Note that it is not case
  #                  or Symbol-sensitive, so :mongrel would work also
  # [+box+]          A Rush::Box subclass instance, ex. Rush::RemoteBox
  # [+*options+]     Options to be passed to [ServiceName]Instance.new
  # === Returns
  # Newly instantiated Rush::Service::[ServiceName]Instance object
  # === Raises
  # nothing
  def self.factory(service_name, box, *options)
    klass = "Rush::Service::#{service_name.to_s.camelize}Instance"
    Kernel.qualified_const_get(klass).new(box, *options)
  end
  
  ##
  # Migrates the instance from its current box to another
  # === Behaviors
  # * Stops the instance on the current box and starts a new instance on the
  #   destination box using the same options.
  # === Parameters
  # [+dst+] Rush::Box subclass instance
  # === Returns
  # The newly started instance
  # === Raises
  # nothing
  def migrate(dst)
    self.stop
    new_instance = self.class.new(@box, @options)
    new_instance.start
    return new_instance
  end

  def start(*options); end
  
  def stop(*options); end
  
  def restart(*options); end
  
  def status(*options); end
  
  ##### Misc #####
  
  def to_sym # :nodoc:
    self.service_name.underscore.to_sym
  end
  
  def self.service_name
    self.to_s =~ /(\w*?)Instance$/
    return $1
  end
  
end