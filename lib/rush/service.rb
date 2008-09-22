##
# === Creating new services
# To create new services, you need to create two subclasses, one from this
# (Rush::Service), and another from Rush::ServiceInstance. They must
# be named Rush::Service::[ServiceName] and
# Rush::Service::[ServiceName]Instance, respectively.
# 
# Your Rush::Service subclass needs to define an +instances+ method
# that checks the box to see what is already running (probably via bash's +ps+),
# and creates an array of ServiceInstance subclasses representing what is running
# on the server (see +instances+ documentation for more information).
# 
# Your Rush::ServiceInstance subclass needs to define +start+, +stop+, 
# +status+, and possibly +restart+ (by default restart just calls +stop+ and
# +start+). Also, to_s should be a form of semi-verbose status. For examlpe,
# a Mongrel service instance would report "port - status" in to_s, and a Clusterip
# instance would report "ip - status".
class Rush::Service
  attr_accessor :name, :box
  
  ##
  # For creating new Rush::Service *subclass* instances.
  # 
  # You can call new on a subclass to initialize a Service object
  # (e.g. Rush::Service::Mongrel.new(box)), or use
  # Rush::Service.factory. One is almost always cleaner than the other.
  # === Behaviors
  # * Stores all +*option+ values in their own instance variable
  # * stores the box, name, and options in instance variables
  # === Parameters
  # [+box+]      A Rush::Box subclass instance, ex. Rush::RemoteBox
  # [+*options+] Options for creation on initializing the particular Service,
  #              and that will be passed to the ServiceInstance objects it
  #              initializes (via +instance+).
  #              Ex, all mongrel service instances might need to know what
  #              environment to run in. Thus, you could pass in :environment =>
  #              "development" to have all instances created by the service
  #              run in development mode (via passing that option in at instance
  #              creation).
  # 
  #              It is interesting to note that +*options+ can take unix-like
  #              flags that will automatically be set to true in the options
  #              hash. For example, 
  #              Service.new(box, :debug_mode, :environment => "development")
  #              would produce an options hash of 
  #              {:debug_mode => true, :environment => "development"}. 
  #              Caveat: flags MUST come before key-value options. See 
  #              +Enumerable#to_options_hash+ for more info.
  # === Returns
  # Nothing in particular
  # === Raises
  # * RuntimeError if new is called from Rush::Service
  def initialize(box, *options)
    if self.class == Rush::Service
      raise "Cannot call new from Rush::Service - use factory instead"
    end
    
    @name = self.class.service_name
    @box = box

    initialize_options(self.class.final_options(*options))
  end
  
  ##
  # Creates a new Rush::Service subclass instance based on the +name+
  # parameter like "Rush::Service::Name"
  # 
  # Ex. self.factory(:test, box) would call Rush::Service::Test.new(box)
  # === Parameters
  # [+name+]     a symbol representing the service name, ex: +:mongrel+.
  #              Note that it is not case sensitive (i.e. it capitalizes it
  #              for you)
  # [+box+]      a Rush::Box subclass instance (ex. Rush::RemoteBox)
  # [+*options+] Options to be passed to [Service].new
  # === Returns
  # Newly instantiated Rush::Service::[Name] object
  # === Raises
  # nothing
  def self.factory(name, box, *options)
    klass = "Rush::Service::#{name.to_s.capitalize}"
    Kernel.qualified_const_get(klass).new(box, *options)
  end

  ##### Instance Methods #####

  ##
  # Creates an instance of the service using both the options set on this
  # service (which are usually defaults form a config file) as well as 
  # +*options+ given. Anything in +*options+ will override this services
  # options.
  # 
  # Note that this does not 'start' the instance on the box. Usage would be:
  # 
  # mongrel_instance = box[:mongrel].instance(:port => 3000)
  # mongrel_instance.status => "not running"
  # mongrel_instance.start  => true
  # mongrel_instance.status => "running"
  #
  # (note that box[:mongrel] is shorthand for Rush::Service.factory(:mongrel, box))
  # === Parameters
  # [+*options+] Options for Rush::Service::[Service]Instance.new, e.g. :port or :ip
  # === Returns
  # A newly instantiated Rush::Service::[Service]Instance object
  # === Raises
  # nothing
  def instance(*options)
    all_options = @options.merge(options.to_options_hash)
    Rush::ServiceInstance.factory(@name, @box, all_options)
  end

  ##
  # Calls status on all of the ServiceInstances configured to be running
  # === Parameters
  # [+*options+] Passes these on to 
  def status(*options)
    # TODO: this is *not* how it's supposed to work. This will only give the
    # status of all *running* instances. There is no way to define what is
    # /supposed/ to be running ATM, though.
    statuses = []
    self.instances.each {|instance| statuses << instance.to_s}
    
    return statuses
  end
  
  ##
  # Migrates all of the services from the services' box to another
  # === Behaviors
  # * calls Rush::ServiceInstance#migrate on all instances of the service
  #   on the box, passing +*options+ to each.
  # === Parameters
  # [+dst+]      A Rush::Box subclass object (ex. Rush::RemoteBox)
  # [+*options+] Rush::ServiceInstance migrate options
  # === Returns
  # Nothing in partucular
  # === Raises
  # Nothing
  def migrate(dst, *options)
    self.instances.each { |instance| instance.migrate(dst, *options) }
  end
  
  # Needs to be defined in subclasses. Must return an array
  # of Rush::ServiceInstance subclass objects.
  def instances; end

  ##### Class Methods #####
  
  def self.status(*boxes)
    statuses = {}
    $boxes.each {|box| statuses[box.host] = box[self.to_sym].status }
    
    return statuses
  end


  ##### Misc #####

  def to_s
    puts status
  end

  def to_sym
    self.name.underscore.to_sym
  end
  
  def self.service_name
    self.to_s.split("::").last
  end
  
  def self.to_sym
    self.service_name.underscore.to_sym
  end
  
  ##
  # Merges author-defined default options from 
  # Rush::Service::[Service]::DEFAULTS, config file options (usually from
  # ~/.rush/config.yml), and +*options+ into one options hash.
  # Author-defined defaults are loaded first and will be overwritten by any
  # options in the config file, which in turn will be overwritten by anything
  # passed into +*options+
  # === Parameters
  # [+*options+] An array of options to be turned into an options hash. See
  #              Enumerable#to_options_hash.
  # === Returns
  # A Hash containing the merging of options as described above.
  # === Raises
  # Nothing
  def self.final_options(*options)
    begin
      defaults = self::DEFAULTS
    rescue NameError
      defaults = {}
    end
    config_options = Rush::Config.load_yaml(:section => self.to_sym)
    these_options = options.to_options_hash
    final_options = defaults.merge(config_options).merge(these_options)
  end
end
