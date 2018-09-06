module XcodeInstall
  class Simulator
    attr_reader :version
    attr_reader :name
    attr_reader :identifier
    attr_reader :source
    attr_reader :xcode

    def initialize(downloadable)
      @version = Gem::Version.new(downloadable['version'])
      @install_prefix = apply_variables(downloadable['userInfo']['InstallPrefix'])
      @name = apply_variables(downloadable['name'])
      @identifier = apply_variables(downloadable['identifier'])
      @source = apply_variables(downloadable['source'])
    end

    def installed?
      # FIXME: use downloadables' `InstalledIfAllReceiptsArePresentOrNewer` key
      File.directory?(@install_prefix)
    end

    def installed_string
      installed? ? 'installed' : 'not installed'
    end

    def to_s
      "#{name} (#{installed_string})"
    end

    def xcode
      Installer.new.installed_versions.find do |x|
        x.available_simulators.find do |s|
          s.version == version
        end
      end
    end

    def download(progress, progress_block = nil)
      result = Curl.new.fetch(
        url: source,
        directory: CACHE_DIR,
        progress: progress,
        progress_block: progress_block
      )
      result ? dmg_path : nil
    end

    def install(progress, should_install)
      dmg_path = download(progress)
      fail Informative, "Failed to download #{@name}." if dmg_path.nil?

      return unless should_install
      prepare_package unless pkg_path.exist?
      puts "Please authenticate to install #{name}..."
      `sudo installer -pkg #{pkg_path} -target /`
      fail Informative, "Could not install #{name}, please try again" unless installed?
      source_receipts_dir = '/private/var/db/receipts'
      target_receipts_dir = "#{@install_prefix}/System/Library/Receipts"
      FileUtils.mkdir_p(target_receipts_dir)
      FileUtils.cp("#{source_receipts_dir}/#{@identifier}.bom", target_receipts_dir)
      FileUtils.cp("#{source_receipts_dir}/#{@identifier}.plist", target_receipts_dir)
      puts "Successfully installed #{name}"
    end

    :private

    def prepare_package
      puts 'Mounting DMG'
      mount_location = Installer.new.mount(dmg_path)
      puts 'Expanding pkg'
      expanded_pkg_path = CACHE_DIR + identifier
      FileUtils.rm_rf(expanded_pkg_path)
      `pkgutil --expand #{mount_location}/*.pkg #{expanded_pkg_path}`
      puts "Expanded pkg into #{expanded_pkg_path}"
      puts 'Unmounting DMG'
      `umount #{mount_location}`
      puts 'Setting package installation location'
      package_info_path = expanded_pkg_path + 'PackageInfo'
      package_info_contents = File.read(package_info_path)
      File.open(package_info_path, 'w') do |f|
        f << package_info_contents.sub('pkg-info', %(pkg-info install-location="#{@install_prefix}"))
      end
      puts 'Rebuilding package'
      `pkgutil --flatten #{expanded_pkg_path} #{pkg_path}`
      FileUtils.rm_rf(expanded_pkg_path)
    end

    def dmg_path
      CACHE_DIR + Pathname.new(source).basename
    end

    def pkg_path
      CACHE_DIR + "#{identifier}.pkg"
    end

    def apply_variables(template)
      variable_map = {
        '$(DOWNLOADABLE_VERSION_MAJOR)' => version.to_s.split('.')[0],
        '$(DOWNLOADABLE_VERSION_MINOR)' => version.to_s.split('.')[1],
        '$(DOWNLOADABLE_IDENTIFIER)' => identifier,
        '$(DOWNLOADABLE_VERSION)' => version.to_s
      }.freeze
      variable_map.each do |key, value|
        next unless template.include?(key)
        template.sub!(key, value)
      end
      template
    end
  end
end
