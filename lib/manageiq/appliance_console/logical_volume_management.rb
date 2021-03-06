require 'linux_admin'
require 'fileutils'

module ManageIQ
module ApplianceConsole
  class LogicalVolumeManagement
    include ManageIQ::ApplianceConsole::Logging

    # Required instantiation parameters
    attr_accessor :disk, :mount_point, :name

    # Derived or optionally provided instantiation parameters
    attr_accessor :volume_group_name, :filesystem_type, :logical_volume_path

    # Logical Disk creation objects
    attr_reader :logical_volume, :partition, :physical_volume, :volume_group

    def initialize(options = {})
      # Required instantiation parameters
      self.disk        = options[:disk]        || raise(ArgumentError, "disk object required")
      self.mount_point = options[:mount_point] || raise(ArgumentError, "mount point required")
      self.name        = options[:name]        || raise(ArgumentError, "unique name required")

      # Derived or optionally provided instantiation parameters
      self.volume_group_name   ||= "vg_#{name}"
      self.filesystem_type     ||= "xfs"
      self.logical_volume_path ||= "/dev/#{volume_group_name}/lv_#{name}"
    end

    # Helper method
    def setup
      create_partition_to_fill_disk
      create_physical_volume
      create_volume_group
      create_logical_volume_to_fill_volume_group
      format_logical_volume
      update_fstab
      lazy_unmount_mount_point
      mount_disk
    end

    private

    def create_partition_to_fill_disk
      # Check if you need to create a GPT part table or a MSDOS one in base of
      # max size of partition table
      max_msdos_ptable_size = 2.terabyte
      self.disk = LinuxAdmin::Disk.local.find { |d| d.path == disk.path }

      partition_type = disk.size >= max_msdos_ptable_size ? 'gpt' : 'msdos'
      disk.create_partition_table(partition_type)

      AwesomeSpawn.run!("parted -s #{disk.path} mkpart primary 0% 100%")
      @partition = disk.partitions.first
    end

    def create_physical_volume
      @physical_volume = LinuxAdmin::PhysicalVolume.create(partition)
    end

    def create_volume_group
      @volume_group = LinuxAdmin::VolumeGroup.create(volume_group_name, physical_volume)
    end

    def create_logical_volume_to_fill_volume_group
      @logical_volume = LinuxAdmin::LogicalVolume.create(logical_volume_path, volume_group, 100)
    end

    def format_logical_volume
      AwesomeSpawn.run!("mkfs.#{filesystem_type} #{logical_volume.path}")
    end

    def lazy_unmount_mount_point
      AwesomeSpawn.run!("umount", :params => ["-l", mount_point.to_s]) if File.file?("/proc/mounts") && File.read("/proc/mounts").include?(" #{mount_point} ")
    end

    def mount_disk
      if mount_point.symlink?
        FileUtils.rm_rf(mount_point)
        FileUtils.mkdir_p(mount_point)
      end
      AwesomeSpawn.run!("mount", :params => ["-a"])
    end

    def update_fstab
      fstab = LinuxAdmin::FSTab.instance
      entry = fstab.entries.find { |e| e.mount_point == mount_point.to_s } || LinuxAdmin::FSTabEntry.new
      fstab.entries.delete(entry)

      entry.device        = logical_volume_path
      entry.mount_point   = mount_point
      entry.fs_type       = filesystem_type
      entry.mount_options = "rw,noatime"
      entry.dumpable      = 0
      entry.fsck_order    = 0

      fstab.entries << entry
      fstab.write!
    end
  end
end
end
