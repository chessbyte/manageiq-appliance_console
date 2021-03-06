require "awesome_spawn"
require "fileutils"
require "linux_admin"
require 'net/scp'
require "manageiq/appliance_console/message_configuration"

module ManageIQ
  module ApplianceConsole
    class MessageClientConfiguration < MessageConfiguration
      attr_reader :server_hostname, :server_username, :server_password, :installed_files

      def initialize(options = {})
        super(options)

        @server_hostname = options[:server_hostname]
        @server_username = options[:server_usernamed] || "root"
        @server_password = options[:server_password]

        @installed_files = [client_properties_path, messaging_yaml_path, truststore_path]
      end

      def activate
        begin
          configure_messaging_yaml          # Set up the local message client in case EVM is actually running on this, Message Server
          create_client_properties          # Create the client.properties configuration fle
          fetch_truststore_from_server      # Fetch the Java Keystore from the Kafka Server
          configure_messaging_type("kafka") # Settings.prototype.messaging_type = 'kafka'
          restart_evmserverd
        rescue AwesomeSpawn::CommandResultError => e
          say(e.result.output)
          say(e.result.error)
          say("")
          say("Failed to Configure the Message Client- #{e}")
          return false
        rescue => e
          say("Failed to Configure the Message Client- #{e}")
          return false
        end
        true
      end

      def ask_for_parameters
        say("\nMessage Client Parameters:\n\n")

        @server_hostname = ask_for_string("Message Server Hostname")
        @server_username = ask_for_string("Message Server Username", server_username)
        @server_password = ask_for_password("Message Server Password")

        @username  = ask_for_string("Message Key Username", username)
        @password  = ask_for_password("Message Key Password")
      end

      def show_parameters
        say("\nMessage Client Configuration:\n")
        say("Message Client Details:\n")
        say("  Message Server Hostname:   #{server_hostname}\n")
        say("  Message Server Username:   #{server_username}\n")
        say("  Message Key Username:      #{username}\n")
      end

      private

      def fetch_truststore_from_server
        say(__method__.to_s.tr("_", " ").titleize)

        return if file_found?(truststore_path)

        Net::SCP.start(server_hostname, server_username, :password => server_password) do |scp|
          scp.download!(truststore_path, truststore_path)
        end

        File.exist?(truststore_path)
      rescue => e
        say("Failed to fetch server truststore: #{e.message}")
        false
      end

      def deactivate
        configure_messaging_type("miq_queue") # Settings.prototype.messaging_type = 'miq_queue'
        restart_evmserverd
        remove_installed_files
      end
    end
  end
end
