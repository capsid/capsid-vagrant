# -*- mode: ruby -*-
# vi: set ft=ruby :


### First of all, let's use two YAML files, vagrant.yml and local.yml, to configure
### what we do. The vagrant.yml is required to exist. The local.yml is not, but
### overrides settings in vagrant.yml. This allows us to move stuff outside the 
### core Vagrantfile. This same technique can be used to inject keys into Vagrant
### without using environment variables. We can also .gitignore local.yml, so that 
### can remain secret. 

require 'yaml'

### Shamelessly stolen from http://apidock.com/rails/v3.2.13/Hash/deep_merge%21
### Required to merge configuration data deeply. 
def deep_merge!(hash, other_hash)
  other_hash.each_pair do |k,v|
    tv = hash[k]
    hash[k] = tv.is_a?(Hash) && v.is_a?(Hash) ? deep_merge!(tv, v) : v
  end
  hash
end

$VAGRANT_CONFIG = YAML.load_file('vagrant.yml')
if File.file?('vagrant_local.yml')
  user_settings = YAML.load_file('vagrant_local.yml')
else 
  user_settings = {}
end 
$VAGRANT_CONFIG = deep_merge!($VAGRANT_CONFIG, user_settings)

# require 'json'
# puts JSON.dump($VAGRANT_CONFIG)

# Now do the bulk of the configuration for Vagrant. This is a Ruby-driven multi-machine
# setup. 

VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  worker_vm_count = $VAGRANT_CONFIG['component_counts']['workers']
  database_vm_count = $VAGRANT_CONFIG['component_counts']['database']

  enable_master = $VAGRANT_CONFIG['enable_components']['master']
  enable_webserver = $VAGRANT_CONFIG['enable_components']['webserver']
  enable_workers = $VAGRANT_CONFIG['enable_components']['workers']
  enable_database = $VAGRANT_CONFIG['enable_components']['database']

  @ansible_groups = {
    "grid-master" => ["master"],
    "webapp" => ["webserver"],
    "grid-worker" => (1..worker_vm_count).collect{ |i| "worker-#{i}" },
    "database" => (1..database_vm_count).collect{ |i| "database-#{i}" },
    "all_groups:children" => ["grid-master", "grid-worker", "database", "webapp"]
  }

  # Calculate a set of static addresses. We might not even use these, but VirtualBox 
  # is a bit funky about DHCP, so it's far easiest to use our own addresses and write
  # them in. For everything else, let's hope to goodness that we have a working DHCP.
  @ansible_ip_addresses = {}
  @address_low = 4

  def get_next_address() 
    address = "192.168.50.#{@address_low}"
    @address_low = @address_low + 1
    return address
  end

  @ansible_ip_addresses["master"] = get_next_address()
  @ansible_ip_addresses["webserver"] = get_next_address()

  (1..worker_vm_count).each do |i|
    @ansible_ip_addresses["worker-#{i}"] = get_next_address()
  end

  (1..database_vm_count).each do |i|
    @ansible_ip_addresses["database-#{i}"] = get_next_address()
  end

  # Core routine to provide basic configuration of a virtual machine. This is 
  # refactoring convenience, to avoid duplicating stuff everywhere. 
  def configure_virtual_machine(machine_name, machine_role, machine) 
    machine.vm.box = "precise64"

    machine.vm.provider :virtualbox do |vb, override|
      vb.gui = false
      vb.customize ["modifyvm", :id, "--memory", "1024"]

      # For VirtualBox, and only for VirtualBox, override private networking to use our specified address
      override.vm.network "private_network", virtualbox__intnet: true, ip: @ansible_ip_addresses[machine_name]
    end

    machine.vm.provider :aws do |aws, override|
      override.vm.box = "dummy"

      aws.access_key_id = $VAGRANT_CONFIG['provider']['aws']['access_key_id']
      aws.secret_access_key = $VAGRANT_CONFIG['provider']['aws']['secret_access_key']
      aws.keypair_name = $VAGRANT_CONFIG['provider']['aws']['keypair_name']
      aws.ami = $VAGRANT_CONFIG['provider']['aws']['ami']
      aws.region = $VAGRANT_CONFIG['provider']['aws']['region']

      # These settings might need to be configured differently for each system
      aws.instance_type = $VAGRANT_CONFIG['provider']['aws']['components'][machine_role]['instance_type']

      override.vm.network "private_network", type: "dhcp"
    end
  end

  def add_storage(machine_name, machine_role, machine)
    machine.vm.provider :virtualbox do |vb|

      storage_root = $VAGRANT_CONFIG['provider']['virtualbox']['storage_root']
      file_to_disk = File.join(storage_root, "data-#{machine_name}.vdi")
      vb.customize ['createhd', '--filename', file_to_disk, '--size', 500 * 1024]
      vb.customize ['storageattach', :id, 
                    '--storagectl', 'SATA Controller', 
                    '--port', 1, 
                    '--device', 0, 
                    '--type', 'hdd', 
                    '--medium', file_to_disk]
    end
  end

  # We use a dummy playbook because (a) we want the ansible provisioner
  # to build an inventory but (b) we want to save the actual provisioning
  # until later so ansible can wire together systems effectively. See the
  # issue at: https://github.com/mitchellh/vagrant/issues/1784
  # There is no realworkaround on this yet. 

  def configure_ansible(machine_name, machine_role, machine)
    machine.vm.provision "ansible" do |ansible|
      ansible.playbook = "dummy-playbook.yml"
      ansible.groups = @ansible_groups
      ansible.extra_vars = { original_hostname: machine_name }
    end
  end

  # Set up the master. There can be only one.  
  if enable_master
    config.vm.define "master" do |master|
      configure_virtual_machine("master", "master", master)
      configure_ansible("master", "master", master)
      add_storage("master", "master", master)
    end
  end

  # For the webserver, add an additional port forward, so that we can get through
  # to the VM on its port 443. This allows us to connect through to the webapp. 
  # Also note that the webserver doesn't need any storage. 
  if enable_webserver
    config.vm.define "webserver" do |webserver|
      configure_virtual_machine("webserver", "webserver", webserver)
      configure_ansible("webserver", "webserver", webserver)
      webserver.vm.network "forwarded_port", guest: 443, host: 8443
    end
  end

  # Set up the worker nodes. There could be n of them. 
  if enable_workers
    (1..worker_vm_count).each do |i|
      vm_name = "worker-#{i}"

      config.vm.define vm_name do |pipeline|
        configure_virtual_machine(vm_name, "worker", pipeline)
        configure_ansible(vm_name, "worker", pipeline)
        add_storage(vm_name, "worker", pipeline)
      end
    end
  end

  # The database should probably also have storage, but it will use it in a very
  # different way, as it ought to be the backing system. We might well even set a 
  # sharded database (at some stage) in which case that becomes an additional thing
  # to worry about. 
  if enable_database
    (1..database_vm_count).each do |i|
      vm_name = "database-#{i}"

      config.vm.define vm_name do |database|
        configure_virtual_machine(vm_name, "database", database)
        configure_ansible(vm_name, "database", database)
      end
    end
  end

end
