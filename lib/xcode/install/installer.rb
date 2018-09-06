module XcodeInstall
  # rubocop:disable Metrics/ClassLength
  class Installer
    attr_reader :xcodes

    def initialize
      FileUtils.mkdir_p(CACHE_DIR)
    end

    def cache_dir
      CACHE_DIR
    end

    def current_symlink
      File.symlink?(SYMLINK_PATH) ? SYMLINK_PATH : nil
    end

    def download(version, progress, url = nil, progress_block = nil)
      xcode = find_xcode_version(version) if url.nil?
      return if url.nil? && xcode.nil?

      dmg_file = Pathname.new(File.basename(url || xcode.path))

      result = Curl.new.fetch(
        url: url || xcode.url,
        directory: CACHE_DIR,
        cookies: url ? nil : spaceship.cookie,
        output: dmg_file,
        progress: progress,
        progress_block: progress_block
      )
      result ? CACHE_DIR + dmg_file : nil
    end

    def find_xcode_version(version)
      # By checking for the name and the version we have the best success rate
      # Sometimes the user might pass
      #   "4.3 for Lion"
      # or they might pass an actual Gem::Version
      #   Gem::Version.new("8.0.0")
      # which should automatically match with "Xcode 8"

      begin
        parsed_version = Gem::Version.new(version)
      rescue ArgumentError
        nil
      end

      seedlist.each do |current_seed|
        return current_seed if current_seed.name == version
        return current_seed if parsed_version && current_seed.version == parsed_version
      end
      nil
    end

    def exist?(version)
      return true if find_xcode_version(version)
      false
    end

    def installed?(version)
      installed_versions.map(&:version).include?(version)
    end

    def installed_versions
      installed.map { |x| InstalledXcode.new(x) }.sort do |a, b|
        Gem::Version.new(a.version) <=> Gem::Version.new(b.version)
      end
    end

    # Returns an array of `XcodeInstall::Xcode`
    #   <XcodeInstall::Xcode:0x007fa1d451c390
    #     @date_modified=2015,
    #     @name="6.4",
    #     @path="/Developer_Tools/Xcode_6.4/Xcode_6.4.dmg",
    #     @url=
    #      "https://developer.apple.com/devcenter/download.action?path=/Developer_Tools/Xcode_6.4/Xcode_6.4.dmg",
    #     @version=Gem::Version.new("6.4")>,
    #
    # the resulting list is sorted with the most recent release as first element
    def seedlist
      @xcodes = Marshal.load(File.read(LIST_FILE)) if LIST_FILE.exist? && xcodes.nil?
      all_xcodes = (xcodes || fetch_seedlist)

      # We have to set the `installed` value here, as we might still use
      # the cached list of available Xcode versions, but have a new Xcode
      # installed in the mean-time
      cached_installed_versions = installed_versions.map(&:bundle_version)
      all_xcodes.each do |current_xcode|
        current_xcode.installed = cached_installed_versions.include?(current_xcode.version)
      end

      all_xcodes.sort_by(&:version)
    end

    def install_dmg(dmg_path, suffix = '', switch = true, clean = true)
      archive_util = '/System/Library/CoreServices/Applications/Archive Utility.app/Contents/MacOS/Archive Utility'
      prompt = "Please authenticate for Xcode installation.\nPassword: "
      xcode_path = "/Applications/Xcode#{suffix}.app"

      if dmg_path.extname == '.xip'
        `'#{archive_util}' #{dmg_path}`
        xcode_orig_path = dmg_path.dirname + 'Xcode.app'
        xcode_beta_path = dmg_path.dirname + 'Xcode-beta.app'
        if Pathname.new(xcode_orig_path).exist?
          `sudo -p "#{prompt}" mv "#{xcode_orig_path}" "#{xcode_path}"`
        elsif Pathname.new(xcode_beta_path).exist?
          `sudo -p "#{prompt}" mv "#{xcode_beta_path}" "#{xcode_path}"`
        else
          out = <<-HELP
No `Xcode.app(or Xcode-beta.app)` found in XIP. Please remove #{dmg_path} if you
suspect a corrupted download or run `xcversion update` to see if the version
you tried to install has been pulled by Apple. If none of this is true,
please open a new GH issue.
HELP
          $stderr.puts out.tr("\n", ' ')
          return
        end
      else
        mount_dir = mount(dmg_path)
        source = Dir.glob(File.join(mount_dir, 'Xcode*.app')).first

        if source.nil?
          out = <<-HELP
No `Xcode.app` found in DMG. Please remove #{dmg_path} if you suspect a corrupted
download or run `xcversion update` to see if the version you tried to install
has been pulled by Apple. If none of this is true, please open a new GH issue.
HELP
          $stderr.puts out.tr("\n", ' ')
          return
        end

        `sudo -p "#{prompt}" ditto "#{source}" "#{xcode_path}"`
        `umount "/Volumes/Xcode"`
      end

      unless verify_integrity(xcode_path)
        `sudo rm -rf #{xcode_path}`
        return
      end

      enable_developer_mode
      xcode = InstalledXcode.new(xcode_path)
      xcode.approve_license
      xcode.install_components

      if switch
        `sudo rm -f #{SYMLINK_PATH}` unless current_symlink.nil?
        `sudo ln -sf #{xcode_path} #{SYMLINK_PATH}` unless SYMLINK_PATH.exist?

        `sudo xcode-select --switch #{xcode_path}`
        puts `xcodebuild -version`
      end

      FileUtils.rm_f(dmg_path) if clean
    end

    # rubocop:disable Metrics/ParameterLists
    def install_version(version, switch = true, clean = true, install = true, progress = true, url = nil, show_release_notes = true, progress_block = nil)
      dmg_path = get_dmg(version, progress, url, progress_block)
      fail Informative, "Failed to download Xcode #{version}." if dmg_path.nil?

      if install
        install_dmg(dmg_path, "-#{version.to_s.split(' ').join('.')}", switch, clean)
      else
        puts "Downloaded Xcode #{version} to '#{dmg_path}'"
      end

      open_release_notes_url(version) if show_release_notes && !url
    end

    def open_release_notes_url(version)
      return if version.nil?
      xcode = seedlist.find { |x| x.name == version }
      `open #{xcode.release_notes_url}` unless xcode.nil? || xcode.release_notes_url.nil?
    end

    def list_annotated(xcodes_list)
      installed = installed_versions.map(&:version)
      xcodes_list.map do |x|
        xcode_version = x.split(' ').first # exclude "beta N", "for Lion".
        xcode_version << '.0' unless xcode_version.include?('.')

        installed.include?(xcode_version) ? "#{x} (installed)" : x
      end.join("\n")
    end

    def list
      list_annotated(list_versions.sort_by(&:to_f))
    end

    def rm_list_cache
      FileUtils.rm_f(LIST_FILE)
    end

    def symlink(version)
      xcode = installed_versions.find { |x| x.version == version }
      `sudo rm -f #{SYMLINK_PATH}` unless current_symlink.nil?
      `sudo ln -sf #{xcode.path} #{SYMLINK_PATH}` unless xcode.nil? || SYMLINK_PATH.exist?
    end

    def symlinks_to
      File.absolute_path(File.readlink(current_symlink), SYMLINK_PATH.dirname) if current_symlink
    end

    def mount(dmg_path)
      plist = hdiutil('mount', '-plist', '-nobrowse', '-noverify', dmg_path.to_s)
      document = REXML::Document.new(plist)
      node = REXML::XPath.first(document, "//key[.='mount-point']/following-sibling::*[1]")
      fail Informative, 'Failed to mount image.' unless node
      node.text
    end

    private

    def spaceship
      @spaceship ||= begin
        begin
          Spaceship.login(ENV['XCODE_INSTALL_USER'], ENV['XCODE_INSTALL_PASSWORD'])
        rescue Spaceship::Client::InvalidUserCredentialsError
          raise 'The specified Apple developer account credentials are incorrect.'
        rescue Spaceship::Client::NoUserCredentialsError
          raise <<-HELP
Please provide your Apple developer account credentials via the
XCODE_INSTALL_USER and XCODE_INSTALL_PASSWORD environment variables.
HELP
        end

        if ENV.key?('XCODE_INSTALL_TEAM_ID')
          Spaceship.client.team_id = ENV['XCODE_INSTALL_TEAM_ID']
        end
        Spaceship.client
      end
    end

    LIST_FILE = CACHE_DIR + Pathname.new('xcodes.bin')
    MINIMUM_VERSION = Gem::Version.new('4.3')
    SYMLINK_PATH = Pathname.new('/Applications/Xcode.app')

    def enable_developer_mode
      `sudo /usr/sbin/DevToolsSecurity -enable`
      `sudo /usr/sbin/dseditgroup -o edit -t group -a staff _developer`
    end

    def get_dmg(version, progress = true, url = nil, progress_block = nil)
      if url
        path = Pathname.new(url)
        return path if path.exist?
      end
      if ENV.key?('XCODE_INSTALL_CACHE_DIR')
        cache_path = Pathname.new(ENV['XCODE_INSTALL_CACHE_DIR']) + Pathname.new("xcode-#{version}.dmg")
        return cache_path if cache_path.exist?
      end

      download(version, progress, url, progress_block)
    end

    def fetch_seedlist
      @xcodes = parse_seedlist(spaceship.send(:request, :post,
                                              '/services-account/QH65B2/downloadws/listDownloads.action').body)

      names = @xcodes.map(&:name)
      @xcodes += prereleases.reject { |pre| names.include?(pre.name) }

      File.open(LIST_FILE, 'wb') do |f|
        f << Marshal.dump(xcodes)
      end

      xcodes
    end

    def installed
      result = `mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null`.split("\n")
      if result.empty?
        result = `find /Applications -name '*.app' -type d -maxdepth 1 -exec sh -c \
        'if [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "{}/Contents/Info.plist" 2>/dev/null)" == "com.apple.dt.Xcode" ]; then echo "{}"; fi' ';'`.split("\n")
      end
      result
    end

    def parse_seedlist(seedlist)
      fail Informative, seedlist['resultString'] unless seedlist['resultCode'].eql? 0

      seeds = Array(seedlist['downloads']).select do |t|
        /^Xcode [0-9]/.match(t['name'])
      end

      xcodes = seeds.map { |x| Xcode.new(x) }.reject { |x| x.version < MINIMUM_VERSION }.sort do |a, b|
        a.date_modified <=> b.date_modified
      end

      xcodes.select { |x| x.url.end_with?('.dmg') || x.url.end_with?('.xip') }
    end

    def list_versions
      seedlist.map(&:name)
    end

    def prereleases
      body = spaceship.send(:request, :get, '/download/').body

      links = body.scan(%r{<a.+?href="(.+?/Xcode.+?/Xcode_(.+?)\.(dmg|xip))".*>(.*)</a>})
      links = links.map do |link|
        parent = link[0].scan(%r{path=(/.*/.*/)}).first.first
        match = body.scan(/#{Regexp.quote(parent)}(.+?.pdf)/).first
        if match
          link + [parent + match.first]
        else
          link + [nil]
        end
      end
      links = links.map { |pre| Xcode.new_prerelease(pre[1].strip.tr('_', ' '), pre[0], pre[4]) }

      if links.count.zero?
        rg = %r{platform-title.*Xcode.* beta.*<\/p>}
        scan = body.scan(rg)

        if scan.count.zero?
          rg = %r{Xcode.* GM.*<\/p>}
          scan = body.scan(rg)
        end

        return [] if scan.empty?

        version = scan.first.gsub(/<.*?>/, '').gsub(/.*Xcode /, '')
        link = body.scan(%r{<button .*"(.+?.(dmg|xip))".*</button>}).first.first
        notes = body.scan(%r{<a.+?href="(/go/\?id=xcode-.+?)".*>(.*)</a>}).first.first
        links << Xcode.new(version, link, notes)
      end

      links
    end

    def verify_integrity(path)
      puts `/usr/sbin/spctl --assess --verbose=4 --type execute #{path}`
      $?.exitstatus.zero?
    end

    def hdiutil(*args)
      io = IO.popen(['hdiutil', *args])
      result = io.read
      io.close
      unless $?.exitstatus.zero?
        file_path = args[-1]
        if `file -b #{file_path}`.start_with?('HTML')
          fail Informative, "Failed to mount #{file_path}, logging into your account from a browser should tell you what is going wrong."
        end
        fail Informative, 'Failed to invoke hdiutil.'
      end
      result
    end
  end
end
