require 'spk/commons/engine'
require 'spk/support/spk_build_images'
require 'spk/support/spk_run'
require 'spk/support/spk_commands'
require 'optparse'
require_relative 'config'
require 'open3'
require 'berkshelf'
require 'fileutils'
require 'pry'


module VagrantPlugins
  module Spk
    class Command < Vagrant.plugin('2', :command)

      def initialize(args, env)
        @params = VagrantPlugins::Spk::Config.new
        @params.mode = args[0]
      end

      def self.synopsis
        'Run a stack locally or build its immutable images'
      end

 			def execute
        OptionParser.new do |opts|
            opts.banner = "Usage: vagrant spk [build-images|run] "\
                          "[-b|--box-url] "\
                          "[-n|--box-name] "\
                          "[-c|--cookbooks-url] "\
                          "[-d|--databags-url] "\
                          "[-k|--ks-template] "\
                          "[-s|--stack-template] "\
                          "[-e|--pre-commands] "\
                          "[-o|--post-commands] "\
                          "[--env-vars] "

            opts.separator ""

            opts.on("-b", "--box-url [URL]", String, "Url of the template box for the virtual machine") do |box_url|
              @params.box_url = box_url
            end

            opts.on("-n", "--box-name [NAME]", String, "Name of the stack virtual machines") do |box_name|
              @params.box_name = box_name
            end

            opts.on("-c", "--cookbooks-url [URL]", String, "URL resolving Berkshelf (Cookbook repo) tar.gz archive") do |cookbooks_url|
              @params.cookbooks_url = cookbooks_url
            end

            opts.on("-d", "--databags-url [URL]", String, "URL resolving Chef databags tar.gz archive") do |databags_url|
              @params.databags_url = databags_url
            end

            opts.on("-k", "--ks-template [PATH]", String, "URL resolving the ks template for the machine (only used by Vagrant Box Image building)") do |ks_template|
              @params.ks_template = ks_template
            end

            opts.on("-s", "--stack-template [PATH]", String, "URL resolving the SPK stack template") do |stack_template|
              @params.stack_template = stack_template
            end

            opts.on("-e", "--pre-commands [PATHS]", String, "Comma-separated list of URLs resolving pre-commands JSON files") do |pre_commands|
              @params.pre_commands = pre_commands
            end

            opts.on("-o", "--post-commands [PATHS]", String, "Comma-separated list of URLs resolving post-commands JSON files") do |post_commands|
              @params.post_commands = post_commands
            end

            opts.on("-v", "--env-vars [PATHS]", String, "Comma-separated list of URLs resolving environment variables JSON files") do |env_vars|
              @params.env_vars = env_vars
            end

            opts.on("-D", "--debug", String, "true, to run packer in debug mode; default is false") do |debug|
              if debug and debug == "true"
                @params.packer_opts = "-debug"
              end
            end

            opts.on("-w", "--why-run [true|false]", String, "Why run mode will just test configuration but will not run or build anything") do |why_run|
              @params.why_run = why_run
            end

        end.parse!


        errors = @params.validate
        abort(errors.join("\n")) if errors.size > 0

        @params.finalize!


        # this code will be run only if the command wasn't asking for helpls
        @engine = VagrantPlugins::Spk::Commons::Engine.new
        @engine.create_work_dir(@params.work_dir)

        nodes = @engine.get_stack_template_nodes(@params.work_dir, @params.stack_template, @params.ks_template)

        # TODO - make it parametric
        Berkshelf::Cli.start(["package",@params.cookbooks_url.split('/')[-1]])

        chef_items = @engine.get_chef_items(nodes, @params.work_dir, @params.cookbooks_url, @params.databags_url)

        env_vars_string = ""
        if @params.env_vars
          file_list = @params.env_vars.split(',')
          env_vars_final = []
          file_list.each do |file|
            env_vars_final << @engine.get_json(@params.work_dir, file.split('/')[-1], file)
          end
          env_vars_final.each do |vars|
            vars.each do |var|
              puts "VAR: #{var}"
              env_vars_string += "export " + var[0] + "=" + var[1] + "\n"
            end
          end
        end


        if !@params.why_run
          #Pre commands
          if @params.pre_commands
            file_list = @params.pre_commands.split(',')
            SpkCommands.new(@params, @engine, file_list, env_vars_string,  "pre").execute!
          end

          # this needs refactoring. every case needs it's own class
          case @params.mode
          when "build-images"
            SpkBuildImages.new(@params,@engine, chef_items).execute!
          when "run"
            SpkRun.new(@params, @engine, nodes).execute!
          end

          # Post Commands
          if @params.post_commands
            file_list = @params.post_commands.split(',')
            SpkCommands.new(@params, @engine, file_list, env_vars_string, "post").execute!
          end
        else
          abort("Why run mode selected - not continuing")
        end
 			end
  	end

  end
end
