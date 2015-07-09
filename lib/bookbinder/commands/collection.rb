Dir.glob(File.expand_path('../../commands/*.rb', __FILE__)).each do |command_file|
  require command_file
end

require_relative '../commands/bind/directory_preparer'
require_relative '../config/bind_config_factory'
require_relative '../config/fetcher'
require_relative '../config/remote_yaml_credential_provider'
require_relative '../config/validator'
require_relative '../config/yaml_loader'
require_relative '../dita_command_creator'
require_relative '../dita_html_to_middleman_formatter'
require_relative '../html_document_manipulator'
require_relative '../ingest/cloner_factory'
require_relative '../ingest/section_repository_factory'
require_relative '../local_file_system_accessor'
require_relative '../middleman_runner'
require_relative '../post_production/sitemap_writer'
require_relative '../preprocessing/copy_to_site_gen_dir'
require_relative '../preprocessing/dita_preprocessor'
require_relative '../preprocessing/preprocessor'
require_relative '../sheller'
require_relative '../subnav_formatter'
require_relative '../values/output_locations'

module Bookbinder
  module Commands
    class Collection
      include Enumerable

      def initialize(logger, base_streams, version_control_system)
        @logger = logger
        @base_streams = base_streams
        @version_control_system = version_control_system
      end

      def each(&block)
        list.each(&block)
      end

      def help
        @help ||= Commands::Help.new(
          logger,
          [version] + standard_commands
        )
      end

      private

      attr_reader :logger, :base_streams, :version_control_system

      def list
        standard_commands + flags
      end

      def flags
        @flags ||= [ version, help ]
      end

      def standard_commands
        @standard_commands ||= [
          Commands::Generate.new(
            local_file_system_accessor,
            Sheller.new,
            Dir.pwd,
            colored_streams
          ),
          build_and_push_tarball,
          bind,
          Commands::PushFromLocal.new(colored_streams, logger, configuration_fetcher, 'acceptance'),
          push_local_to_staging,
          Commands::PushToProd.new(colored_streams, logger, configuration_fetcher, Dir.mktmpdir),
          Commands::RunPublishCI.new(bind, push_local_to_staging, build_and_push_tarball),
          Commands::Tag.new(colored_streams, configuration_fetcher, version_control_system),
          Commands::UpdateLocalDocRepos.new(
            colored_streams,
            configuration_fetcher,
            version_control_system
          ),
        ]
      end

      def version
        @version ||= Commands::Version.new(logger)
      end

      def bind
        @bind ||= Commands::Bind.new(
          colored_streams,
          OutputLocations.new(final_app_dir: final_app_directory, context_dir: File.absolute_path('.')),
          Config::BindConfigFactory.new(version_control_system, configuration_fetcher),
          Config::ArchiveMenuConfiguration.new(loader: config_loader, config_filename: 'bookbinder.yml'),
          local_file_system_accessor,
          MiddlemanRunner.new(logger, version_control_system),
          PostProduction::SitemapWriter.build(logger, final_app_directory, sitemap_port),
          Preprocessing::Preprocessor.new(
            Preprocessing::DitaPreprocessor.new(
              DitaHtmlToMiddlemanFormatter.new(local_file_system_accessor, subnav_formatter, html_document_manipulator),
              local_file_system_accessor,
              DitaCommandCreator.new(ENV['PATH_TO_DITA_OT_LIBRARY']),
              Sheller.new
            ),
            Preprocessing::CopyToSiteGenDir.new(local_file_system_accessor),
          ),
          Ingest::ClonerFactory.new(colored_streams, local_file_system_accessor, version_control_system),
          Ingest::SectionRepositoryFactory.new(logger),
          Commands::BindComponents::DirectoryPreparer.new(logger, local_file_system_accessor, version_control_system)
        )
      end

      def push_local_to_staging
        @push_local_to_staging ||= Commands::PushFromLocal.new(
          colored_streams,
          logger,
          configuration_fetcher,
          'staging'
        )
      end

      def build_and_push_tarball
        @build_and_push_tarball ||= Commands::BuildAndPushTarball.new(
          colored_streams,
          configuration_fetcher
        )
      end

      def colored_streams
        {
          err: Streams::ColorizedStream.new(Colorizer::Colors.red, base_streams[:err]),
          out: base_streams[:out],
          success: Streams::ColorizedStream.new(Colorizer::Colors.green, base_streams[:out]),
          warn: Streams::ColorizedStream.new(Colorizer::Colors.yellow, base_streams[:out]),
        }
      end

      def configuration_fetcher
        @configuration_fetcher ||= Config::Fetcher.new(
          Config::Validator.new(local_file_system_accessor),
          config_loader,
          Config::RemoteYamlCredentialProvider.new(logger, version_control_system)
        ).tap do |fetcher|
          fetcher.set_config_file_path './config.yml'
        end
      end

      def config_loader
        @config_loader ||= Config::YAMLLoader.new
      end

      def final_app_directory
        @final_app_directory ||= File.absolute_path('final_app')
      end

      def subnav_formatter
        @subnav_formatter ||= SubnavFormatter.new
      end

      def html_document_manipulator
        @html_document_manipulator ||= HtmlDocumentManipulator.new
      end

      def local_file_system_accessor
        @local_file_system_accessor ||= LocalFileSystemAccessor.new
      end

      def sitemap_port
        41722
      end
    end
  end
end
