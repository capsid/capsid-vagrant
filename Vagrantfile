# -*- mode: ruby -*-
# vi: set ft=ruby :


### First of all, let's use two YAML files, vagrant.yml and local.yml, to configure
### what we do. The vagrant.yml is required to exist. The local.yml is not, but
### overrides settings in vagrant.yml. This allows us to move stuff outside the 
### core Vagrantfile. This same technique can be used to inject keys into Vagrant
### without using environment variables. We can also .gitignore local.yml, so that 
### can remain secret. 

require 'yaml'

config_settings = YAML.load_file('vagrant.yml')
if File.file?('local.yml')
  user_settings = YAML.load_file('local.yml')
else 
  user_settings = {}
end 
config_settings.merge!(user_settings)

VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  worker_vm_count = config_settings['component_counts']['workers']
  database_vm_count = config_settings['component_counts']['database']

  enable_master = config_settings['enable_components']['master']
  enable_webserver = config_settings['enable_components']['webserver']
  enable_workers = config_settings['enable_components']['workers']
  enable_database = config_settings['enable_components']['database']

  @storage_root = config_settings['storage_root']

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
  def configure_virtual_machine(machine_name, machine) 
    machine.vm.box = "precise64"

    machine.vm.provider :virtualbox do |vb, override|
      vb.gui = false
      vb.customize ["modifyvm", :id, "--memory", "1024"]

      # For VirtualBox, and only for VirtualBox, override private networking to use our specified address
      override.vm.network "private_network", virtualbox__intnet: true, ip: @ansible_ip_addresses[machine_name]
    end
  end

  def add_storage(machine_name, machine)
    machine.vm.provider :virtualbox do |vb|
      file_to_disk = File.join(@storage_root, "data-#{machine_name}.vdi")
      vb.customize ['createhd', '--filename', file_to_disk, '--size', 500 * 1024]
      vb.customize ['storageattach', :id, 
                    '--storagectl', 'SATA Controller', 
                    '--port', 1, 
                    '--device', 0, 
                    '--type', 'hdd', 
                    '--medium', file_to_disk]
    end
  end

  def configure_ansible(machine_name, machine)
    machine.vm.provision "ansible" do |ansible|
      ansible.playbook = "dummy-playbook.yml"
      ansible.groups = @ansible_groups
      ansible.extra_vars = { original_hostname: machine_name }
    end
  end

  # We use a dummy playbook because (a) we want the ansible provisioner
  # to build an inventory but (b) we want to save the actual provisioning
  # until later so ansible can wire together systems effectively. See the
  # issue at: https://github.com/mitchellh/vagrant/issues/1784
  # There is no realworkaround on this yet. 

  if enable_master
    config.vm.define "master" do |master|
      configure_virtual_machine("master", master)
      configure_ansible("master", master)
      add_storage("master", master)
    end
  end

  if enable_webserver
    config.vm.define "webserver" do |webserver|
      configure_virtual_machine("webserver", webserver)
      configure_ansible("webserver", webserver)
      webserver.vm.network "forwarded_port", guest: 443, host: 8443
    end
  end

  if enable_workers
    (1..worker_vm_count).each do |i|
      vm_name = "worker-#{i}"

      config.vm.define vm_name do |pipeline|
        configure_virtual_machine(vm_name, pipeline)
        configure_ansible(vm_name, pipeline)
        add_storage(vm_name, pipeline)
      end
    end
  end

  if enable_database
    (1..database_vm_count).each do |i|
      vm_name = "database-#{i}"

      config.vm.define vm_name do |database|
        configure_virtual_machine(vm_name, database)
        configure_ansible(vm_name, database)
      end
    end
  end

end
